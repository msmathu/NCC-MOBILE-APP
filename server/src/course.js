// Course geometry and progression rules.
// KEEP IN SYNC with client/scripts/course.gd (obstacle positions, finish distance, ranks, unlocks).

export const ROOM_SIZE = 7;
export const COUNTDOWN_SECONDS = 10;
export const RACE_TIMEOUT_MS = 6 * 60 * 1000;
export const RESULTS_LINGER_MS = 60 * 1000;
export const RECONNECT_GRACE_MS = 60 * 1000;

export const FIRST_OBSTACLE_X = 800;
export const OBSTACLE_SPACING = 1000;
export const OBSTACLE_PASS_WIDTH = 200;
export const OBSTACLE_COUNT = 15;
export const SPRINT_LENGTH = 1600; // obstacle 15 is the finish-line sprint
export const FINISH_X = FIRST_OBSTACLE_X + (OBSTACLE_COUNT - 1) * OBSTACLE_SPACING + SPRINT_LENGTH;

// No human can clear the course faster than this; used to reject forged finishes.
export const MIN_FINISH_MS = 45 * 1000;

export const obstacleX = (i) => FIRST_OBSTACLE_X + i * OBSTACLE_SPACING;

export const DIRECTORATES = [
  'Andhra Pradesh & Telangana',
  'Bihar & Jharkhand',
  'Delhi',
  'Gujarat, DNH & DD',
  'Jammu & Kashmir & Ladakh',
  'Karnataka & Goa',
  'Kerala & Lakshadweep',
  'Madhya Pradesh & Chhattisgarh',
  'Maharashtra',
  'North Eastern Region',
  'Odisha',
  'Punjab, Haryana, HP & Chandigarh',
  'Rajasthan',
  'Tamil Nadu, Puducherry & A&N',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal & Sikkim',
];

export const RANKS = [
  { name: 'Cadet', dp: 0 },
  { name: 'Lance Corporal', dp: 300 },
  { name: 'Corporal', dp: 800 },
  { name: 'Sergeant', dp: 1600 },
  { name: 'Under Officer', dp: 3000 },
  { name: 'Senior Under Officer', dp: 5000 },
];

export const rankIndexFor = (dp) => {
  let idx = 0;
  RANKS.forEach((r, i) => { if (dp >= r.dp) idx = i; });
  return idx;
};

// Each customization unlocks at a rank index.
export const UNLOCKS = {
  uniform: { army: 0, navy: 1, air: 2 },
  beret: { maroon: 0, black: 1, blue: 2, green: 3 },
  badge: { none: 0, star: 1, eagle: 3, ashoka: 5 },
};

export const PLACE_DP = [100, 80, 65, 55, 45, 40, 35];
export const FINISH_BONUS_DP = 20;
export const DNF_DP = 10;

export const ROLES = ['leader', 'scout', 'support'];

// A match is a 3-level camp competition: L1 obstacle course, L2 target practice
// (25 m range, 5 shots, max 50), L3 map reading (5 clues, max 50).
export const STAGE_MS = { range: 100 * 1000, map: 150 * 1000 };
export const STAGE_MAX_SCORE = 50;
// Camp points for 1st..7th in each level; the total decides the match.
export const STAGE_POINTS = [10, 8, 6, 5, 4, 3, 2];

export const BOT_NAMES = [
  'Cdt Arjun', 'Cdt Priya', 'Cdt Rohan', 'Cdt Meera', 'Cdt Kabir', 'Cdt Ananya',
  'Cdt Vikram', 'Cdt Sneha', 'Cdt Aditya', 'Cdt Kavya', 'Cdt Ishaan', 'Cdt Diya',
];
