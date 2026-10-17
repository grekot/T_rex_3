// `node test/youtube.test.mjs` - testy obsługi YouTube API, bez sieci
import assert from "node:assert/strict";
import {
  isValidChannelId,
  playlistIds,
  buildStatsUrl,
  buildPlaylistUrl,
  buildVideosUrl,
  parseStatsResponse,
  parsePlaylistResponse,
  parseDuration,
  parseVideosResponse,
} from "../utils/youtube.js";

const CHANNEL = "UC_x5XG1OV2P6uZZ5FSM9Ttw";

assert.equal(isValidChannelId(CHANNEL), true);
assert.equal(isValidChannelId("UC_x5XG1OV2P6uZZ5FSM9Tt"), false);
assert.equal(isValidChannelId("@mojkanal"), false);
assert.equal(isValidChannelId(""), false);
assert.equal(isValidChannelId(undefined), false);

// playlisty systemowe
assert.deepEqual(playlistIds(CHANNEL), {
  uploads: "UU_x5XG1OV2P6uZZ5FSM9Ttw",
  videos: "UULF_x5XG1OV2P6uZZ5FSM9Ttw",
  shorts: "UUSH_x5XG1OV2P6uZZ5FSM9Ttw",
  live: "UULV_x5XG1OV2P6uZZ5FSM9Ttw",
});

// adresy
const url = buildStatsUrl(CHANNEL, "AIza&test");
assert.ok(url.startsWith("https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics&id=" + CHANNEL + "&key="));
assert.ok(url.endsWith("key=AIza%26test"), "klucz musi być zakodowany w URL");
assert.equal(
  buildPlaylistUrl("UUSH_x5XG1OV2P6uZZ5FSM9Ttw", "k"),
  "https://www.googleapis.com/youtube/v3/playlistItems?part=contentDetails&playlistId=UUSH_x5XG1OV2P6uZZ5FSM9Ttw&maxResults=1&key=k"
);
assert.equal(
  buildVideosUrl(["abc", "d-f"], "k"),
  "https://www.googleapis.com/youtube/v3/videos?part=snippet,statistics,contentDetails&id=abc,d-f&key=k"
);

// statystyki kanału
const okBody = {
  items: [
    {
      snippet: { title: "Mój kanał" },
      statistics: { viewCount: "123456", subscriberCount: "4200", hiddenSubscriberCount: false, videoCount: "57" },
    },
  ],
};
let r = parseStatsResponse(200, JSON.stringify(okBody));
assert.equal(r.ok, true);
assert.equal(r.stats.title, "Mój kanał");
assert.equal(r.stats.subscribers, 4200);
assert.equal(r.stats.views, 123456);
assert.equal(r.stats.videos, 57);
assert.ok(typeof r.stats.fetchedAt === "number" && r.stats.fetchedAt > 0);

// body już jako obiekt (tak też potrafi zwrócić fetch w Zepp OS)
r = parseStatsResponse(200, okBody);
assert.equal(r.ok, true);

// ukryty licznik subskrybentów
r = parseStatsResponse(200, { items: [{ snippet: { title: "X" }, statistics: { hiddenSubscriberCount: true, viewCount: "1" } }] });
assert.equal(r.ok, true);
assert.equal(r.stats.subscribers, null);

// złe ID kanału -> pusta lista
r = parseStatsResponse(200, { items: [] });
assert.equal(r.ok, false);
assert.match(r.error, /Nie znaleziono kanału/);

// zły klucz API
r = parseStatsResponse(400, { error: { code: 400, message: "API key not valid. Please pass a valid API key." } });
assert.equal(r.ok, false);
assert.match(r.error, /Klucz API odrzucony/);

// limit / brak uprawnień
r = parseStatsResponse(403, { error: { code: 403, message: "quotaExceeded" } });
assert.equal(r.ok, false);
assert.match(r.error, /quotaExceeded/);

// śmieci zamiast JSON
r = parseStatsResponse(502, "<html>Bad Gateway</html>");
assert.equal(r.ok, false);

// HTTP 500 bez pola error
r = parseStatsResponse(500, {});
assert.equal(r.ok, false);
assert.equal(r.error, "HTTP 500");

// playlista: pierwszy film
r = parsePlaylistResponse(200, { items: [{ contentDetails: { videoId: "vid123" } }] });
assert.deepEqual(r, { ok: true, videoId: "vid123" });
r = parsePlaylistResponse(200, { items: [{ snippet: { resourceId: { videoId: "vid456" } } }] });
assert.deepEqual(r, { ok: true, videoId: "vid456" });
r = parsePlaylistResponse(200, { items: [] });
assert.equal(r.ok, false);
assert.equal(r.notFound, true);
r = parsePlaylistResponse(404, {
  error: { code: 404, message: "The playlist identified with the request's playlistId parameter cannot be found.", errors: [{ reason: "playlistNotFound" }] },
});
assert.equal(r.ok, false);
assert.equal(r.notFound, true);
r = parsePlaylistResponse(403, { error: { code: 403, message: "quotaExceeded", errors: [{ reason: "quotaExceeded" }] } });
assert.equal(r.ok, false);
assert.equal(r.notFound, false);

// czas trwania
assert.equal(parseDuration("PT45S"), 45);
assert.equal(parseDuration("PT12M34S"), 754);
assert.equal(parseDuration("PT1H2M3S"), 3723);
assert.equal(parseDuration("PT2H"), 7200);
assert.equal(parseDuration("P0D"), 0);
assert.equal(parseDuration(undefined), 0);

// statystyki filmów
r = parseVideosResponse(200, {
  items: [
    {
      id: "vid123",
      snippet: { title: "Film 1", publishedAt: "2026-10-10T12:00:00Z", liveBroadcastContent: "none" },
      contentDetails: { duration: "PT12M34S" },
      statistics: { viewCount: "1234", likeCount: "56", commentCount: "7" },
    },
    {
      id: "short1",
      snippet: { title: "Short", publishedAt: "2026-10-15T08:30:00Z", liveBroadcastContent: "none" },
      contentDetails: { duration: "PT45S" },
      statistics: { viewCount: "999" },
    },
  ],
});
assert.equal(r.ok, true);
assert.equal(r.videos.vid123.title, "Film 1");
assert.equal(r.videos.vid123.views, 1234);
assert.equal(r.videos.vid123.likes, 56);
assert.equal(r.videos.vid123.comments, 7);
assert.equal(r.videos.vid123.durationSec, 754);
assert.equal(r.videos.vid123.publishedAt, Date.parse("2026-10-10T12:00:00Z"));
assert.equal(r.videos.vid123.live, false);
assert.equal(r.videos.short1.likes, null, "ukryte polubienia -> null");
assert.equal(r.videos.short1.comments, null, "wyłączone komentarze -> null");
assert.equal(r.videos.short1.durationSec, 45);

r = parseVideosResponse(403, { error: { code: 403, message: "quotaExceeded" } });
assert.equal(r.ok, false);

console.log("youtube: WSZYSTKIE TESTY OK");
