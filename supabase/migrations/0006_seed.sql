-- StudyTrail — seed catalog data (badges + a default class).
-- Idempotent: safe to re-run.

-- Default class for the CSPIT / Charusat cohort so the leaderboard has a home.
insert into classes (name, college, branch, batch)
select 'CE-A 2025', 'CSPIT, Charusat University', 'Computer Engineering', '2025'
where not exists (select 1 from classes where name = 'CE-A 2025');

-- Achievement catalog. icon_key / color_key mirror the UI's token names.
insert into badges (key, name, icon_key, color_key, description) values
  ('first_step',    'First Step',      'flag',          'sky',    'Complete your first study task.'),
  ('week_warrior',  'Week Warrior',    'local_fire_department', 'amber', 'Maintain a 7-day streak.'),
  ('quiz_ace',      'Quiz Ace',        'quiz',          'violet', 'Score 100% on any quiz.'),
  ('card_master',   'Card Master',     'style',         'emerald','Review 100 flashcards.'),
  ('night_owl',     'Night Owl',       'nightlight',    'indigo', 'Study after 10 PM.'),
  ('early_bird',    'Early Bird',      'wb_sunny',      'orange', 'Study before 7 AM.'),
  ('focused_mind',  'Focused Mind',    'self_improvement','teal', 'Finish 10 Pomodoro sessions.'),
  ('roadmap_ready', 'Roadmap Ready',   'map',           'rose',   'Generate your first AI roadmap.'),
  ('curious_learner','Curious Learner','chat',          'cyan',   'Ask the AI tutor 25 questions.'),
  ('goal_crusher',  'Goal Crusher',    'emoji_events',  'gold',   'Reach 100% on a goal.')
on conflict (key) do nothing;
