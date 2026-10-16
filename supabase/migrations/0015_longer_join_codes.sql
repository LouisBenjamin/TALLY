-- TALLY — longer join codes
--
-- 0001 made join codes the first 6 hex characters of a UUID: 16.7M options,
-- and join_group_by_code has no rate limit, so a script can guess its way into
-- real groups (with 50 groups, about one hit per 335k guesses). New groups get
-- 10 hex characters (~1.1 trillion options) from the same random source.
-- The first 12 hex digits of a v4 UUID are all random (the version nibble
-- comes after), so taking 10 of them loses no entropy. No pgcrypto needed.
--
-- shortcut: existing 6-character codes keep working so invites already sent
-- don't break. To close the hole for them too, rotate them (old links die):
--   update groups set join_code = default where length(join_code) = 6;

alter table groups
  alter column join_code
  set default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
