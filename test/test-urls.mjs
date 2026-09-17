export const PORT = process.env.TEST_PORT || process.env.STRAVA_TEST_PORT || "8080";
export const HOST = process.env.TEST_HOST || "localhost";
export const BASE = `http://${HOST}:${PORT}/strava/me`;
export const CGI  = `http://${HOST}:${PORT}/cgi-bin`;
export const URLS = {
  club: `http://${HOST}:${PORT}/strava/index.html`,
  dash: `${BASE}/index.html`,
  stats: `${BASE}/stats.html`,
  heatmap: `${BASE}/heatmap.html`,
  activity: `${BASE}/activity.html?id=18784255013`,
  activityHealthsyncRun: `${BASE}/activity.html?id=2026-06-22-15-07-running`,
  activityHealthsyncCycling: `${BASE}/activity.html?id=2026-06-22-10-30-cycling`,
  activityMagene: `${BASE}/activity.html?id=magene-2026-07-12-50671559`,
  activityWalk: `${BASE}/activity.html?id=3`,
  bike: `${BASE}/bike.html`,
};
