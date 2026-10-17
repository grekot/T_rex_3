// Budowanie zapytań do YouTube Data API v3 i czytanie odpowiedzi.
// Czyste funkcje - używa ich Side Service, a testy uruchamia Node.

export const API_BASE = "https://www.googleapis.com/youtube/v3/";
export const API_URL = API_BASE + "channels";

// ID kanału: "UC" + 22 znaki
export function isValidChannelId(id) {
  return /^UC[A-Za-z0-9_-]{22}$/.test(id || "");
}

// YouTube prowadzi dla każdego kanału playlisty systemowe - wystarczy podmienić prefiks "UC":
// UU - wszystkie filmy, UULF - tylko długie filmy, UUSH - tylko Shorts, UULV - transmisje.
export function playlistIds(channelId) {
  const suffix = String(channelId || "").slice(2);
  return {
    uploads: "UU" + suffix,
    videos: "UULF" + suffix,
    shorts: "UUSH" + suffix,
    live: "UULV" + suffix,
  };
}

export function buildStatsUrl(channelId, apiKey) {
  return (
    API_BASE +
    "channels?part=snippet,statistics&id=" +
    encodeURIComponent(channelId) +
    "&key=" +
    encodeURIComponent(apiKey)
  );
}

export function buildPlaylistUrl(playlistId, apiKey, maxResults = 1) {
  return (
    API_BASE +
    "playlistItems?part=contentDetails&playlistId=" +
    encodeURIComponent(playlistId) +
    "&maxResults=" +
    maxResults +
    "&key=" +
    encodeURIComponent(apiKey)
  );
}

export function buildVideosUrl(videoIds, apiKey) {
  return (
    API_BASE +
    "videos?part=snippet,statistics,contentDetails&id=" +
    videoIds.map((id) => encodeURIComponent(id)).join(",") +
    "&key=" +
    encodeURIComponent(apiKey)
  );
}

// Wspólna obsługa odpowiedzi API: { ok: true, data } albo { ok: false, error, code, reason }
export function parseApiBody(status, body) {
  let data = body;
  if (typeof body === "string") {
    try {
      data = JSON.parse(body);
    } catch (e) {
      return { ok: false, error: "Niepoprawna odpowiedź YouTube" };
    }
  }
  if (!data || typeof data !== "object") {
    return { ok: false, error: "Pusta odpowiedź YouTube" };
  }
  if (data.error) {
    const code = data.error.code || status;
    const message = data.error.message || "HTTP " + code;
    const first = data.error.errors && data.error.errors[0];
    const reason = (first && first.reason) || "";
    if (code === 400 || code === 403) {
      return { ok: false, error: "Klucz API odrzucony: " + message, code, reason };
    }
    return { ok: false, error: message, code, reason };
  }
  if (status && status >= 400) {
    return { ok: false, error: "HTTP " + status, code: status, reason: "" };
  }
  return { ok: true, data };
}

// Statystyki kanału: { ok: true, stats } albo { ok: false, error }
export function parseStatsResponse(status, body) {
  const r = parseApiBody(status, body);
  if (!r.ok) return r;
  const item = r.data.items && r.data.items[0];
  if (!item) {
    return { ok: false, error: "Nie znaleziono kanału - sprawdź ID" };
  }
  const st = item.statistics || {};
  return {
    ok: true,
    stats: {
      title: (item.snippet && item.snippet.title) || "",
      // YouTube pozwala ukryć licznik; wtedy subscriberCount nie przychodzi
      subscribers: st.hiddenSubscriberCount ? null : Number(st.subscriberCount || 0),
      views: Number(st.viewCount || 0),
      videos: Number(st.videoCount || 0),
      fetchedAt: Date.now(),
    },
  };
}

// Pierwszy film z playlisty: { ok: true, videoId } albo { ok: false, error, notFound }
export function parsePlaylistResponse(status, body) {
  const r = parseApiBody(status, body);
  if (!r.ok) {
    return { ok: false, error: r.error, notFound: r.code === 404 || r.reason === "playlistNotFound" };
  }
  const item = r.data.items && r.data.items[0];
  const videoId =
    item &&
    ((item.contentDetails && item.contentDetails.videoId) ||
      (item.snippet && item.snippet.resourceId && item.snippet.resourceId.videoId));
  if (!videoId) {
    return { ok: false, error: "Playlista jest pusta", notFound: true };
  }
  return { ok: true, videoId };
}

// Czas trwania w formacie ISO 8601: "PT1H2M3S" -> 3723 sekundy
export function parseDuration(iso) {
  const m = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(iso || "");
  if (!m) return 0;
  return Number(m[1] || 0) * 3600 + Number(m[2] || 0) * 60 + Number(m[3] || 0);
}

// Statystyki filmów: { ok: true, videos: { [id]: {...} } } albo { ok: false, error }
export function parseVideosResponse(status, body) {
  const r = parseApiBody(status, body);
  if (!r.ok) return r;
  const videos = {};
  (r.data.items || []).forEach((item) => {
    const st = item.statistics || {};
    const sn = item.snippet || {};
    const cd = item.contentDetails || {};
    videos[item.id] = {
      id: item.id,
      title: sn.title || "",
      publishedAt: Date.parse(sn.publishedAt || "") || 0,
      durationSec: parseDuration(cd.duration),
      views: Number(st.viewCount || 0),
      // Autor może ukryć polubienia albo wyłączyć komentarze - wtedy pól brak
      likes: st.likeCount === undefined ? null : Number(st.likeCount),
      comments: st.commentCount === undefined ? null : Number(st.commentCount),
      live: sn.liveBroadcastContent === "live",
    };
  });
  return { ok: true, videos };
}
