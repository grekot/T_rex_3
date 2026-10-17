// Side Service - ten kod działa w aplikacji Zepp na telefonie.
// Zegarek nie ma internetu, więc prosi telefon o dane z YouTube.
import { BaseSideService, settingsLib } from "@zeppos/zml/base-side";
import {
  buildStatsUrl,
  buildPlaylistUrl,
  buildVideosUrl,
  parseStatsResponse,
  parsePlaylistResponse,
  parseVideosResponse,
  playlistIds,
  isValidChannelId,
} from "../utils/youtube";

function readSettings() {
  return {
    channelId: (settingsLib.getItem("channelId") || "").trim(),
    apiKey: (settingsLib.getItem("apiKey") || "").trim(),
  };
}

async function getJson(url) {
  const response = await fetch({ url, method: "GET" });
  return { status: response.status, body: response.body };
}

// Najnowszy film z playlisty (1 jednostka limitu)
async function latestVideoId(playlistId, apiKey) {
  try {
    const r = await getJson(buildPlaylistUrl(playlistId, apiKey, 1));
    return parsePlaylistResponse(r.status, r.body);
  } catch (e) {
    return { ok: false, error: "Błąd sieci: " + e, notFound: false };
  }
}

// Jedno odświeżenie = 4 jednostki limitu: kanał + 2 playlisty + statystyki filmów
async function fetchStats() {
  const { channelId, apiKey } = readSettings();
  if (!channelId || !apiKey) {
    return { ok: false, needsSetup: true, error: "Uzupełnij ustawienia w aplikacji Zepp" };
  }
  if (!isValidChannelId(channelId)) {
    return { ok: false, needsSetup: true, error: "ID kanału: UC + 22 znaki" };
  }

  let stats;
  try {
    const r = await getJson(buildStatsUrl(channelId, apiKey));
    const parsed = parseStatsResponse(r.status, r.body);
    if (!parsed.ok) return parsed;
    stats = parsed.stats;
  } catch (e) {
    return { ok: false, error: "Błąd sieci: " + e };
  }

  const ids = playlistIds(channelId);
  let [video, short] = await Promise.all([
    latestVideoId(ids.videos, apiKey),
    latestVideoId(ids.shorts, apiKey),
  ]);
  // Starsze kanały bez podziału na długie/Shorts: weź po prostu ostatni upload
  if (!video.ok && video.notFound) {
    video = await latestVideoId(ids.uploads, apiKey);
  }

  const wanted = [];
  if (video.ok) wanted.push(video.videoId);
  if (short.ok && wanted.indexOf(short.videoId) === -1) wanted.push(short.videoId);

  let videos = {};
  let videosError = null;
  if (wanted.length) {
    try {
      const r = await getJson(buildVideosUrl(wanted, apiKey));
      const parsed = parseVideosResponse(r.status, r.body);
      if (parsed.ok) videos = parsed.videos;
      else videosError = parsed.error;
    } catch (e) {
      videosError = "Błąd sieci: " + e;
    }
  }

  stats.latestVideo = (video.ok && videos[video.videoId]) || null;
  stats.latestShort = (short.ok && videos[short.videoId]) || null;
  stats.videoError = stats.latestVideo
    ? null
    : video.ok
      ? videosError || "Brak danych o filmie"
      : video.notFound
        ? "Kanał nie ma filmów"
        : video.error;
  stats.shortError = stats.latestShort
    ? null
    : short.ok
      ? videosError || "Brak danych o shorcie"
      : short.notFound
        ? "Kanał nie ma shortów"
        : short.error;

  return { ok: true, stats };
}

AppSideService(
  BaseSideService({
    onInit() {},

    onRequest(req, res) {
      if (req.method === "GET_STATS") {
        fetchStats()
          .then((result) => res(null, result))
          .catch((e) => res(null, { ok: false, error: String(e) }));
      } else {
        res(null, { ok: false, error: "Nieznane żądanie: " + req.method });
      }
    },

    // Po zmianie ustawień w telefonie od razu wyślij świeże dane na zegarek
    onSettingsChange({ key }) {
      if (key !== "channelId" && key !== "apiKey") return;
      fetchStats()
        .then((result) => {
          try {
            this.call({ type: "STATS", result });
          } catch (e) {}
        })
        .catch(() => {});
    },

    onRun() {},
    onDestroy() {},
  })
);
