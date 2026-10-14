# Hearthstone Ranked & Arena: how they worked in 2014 (Classic era)

Research date: 2026-10-15. Purpose: reference for reproducing Classic-era ladder/arena rules.

## Sources (abbreviations used below)

- **[GP-Jul14]** Gamepedia wiki "Ranked Play / Play mode", archive capture 2014-07-30:
  http://web.archive.org/web/20140730094110/http://hearthstone.gamepedia.com:80/Ranked_Play
- **[GP-Feb15]** Same page, capture 2015-02-07 (identical rules; also has the star-icon table and season list through Feb 2015):
  http://web.archive.org/web/20150207121459/http://hearthstone.gamepedia.com:80/Ranked
- **[WGG-old]** hearthstone.wiki.gg "Ranked/2013-2020" (current wiki, historical page):
  https://hearthstone.wiki.gg/wiki/Ranked/2013-2020
- **[WGG]** hearthstone.wiki.gg "Ranked" (patch history): https://hearthstone.wiki.gg/wiki/Ranked
- **[BLUE-Aratil]** Blizzard CM Aratil, 2014-01-21, official forums (via HearthPwn blue tracker, archived 2014-07-29):
  http://web.archive.org/web/20140729154859/http://www.hearthpwn.com/blue-tracker/topic/4644-ranks-reset-elo-mmr-stays-the-same-is-this-working
- **[BRODE-Casual]** Ben Brode tweet cited by GP for Casual MMR: https://twitter.com/bdbrode/status/418778828547166209
- **[GP-Arena-Oct14]** Gamepedia wiki "Arena", capture 2014-10-20:
  http://web.archive.org/web/20141020204212/http://hearthstone.gamepedia.com:80/Arena
- **[ZERI]** CM Zeriyah tweet cited by GP for arena matchmaking: https://twitter.com/CM_Zeriyah/status/421056491840229377
- **[WGG-Arena]** https://hearthstone.wiki.gg/wiki/Arena

---

## RANKED (2014)

Ranked Play rules as implemented by Patch 1.0.0.4217 (2013-12-10) + Patch 1.0.0.4944 (2014-03-11, open beta, just before release) and unchanged through all of 2014 [WGG], [GP-Jul14], [GP-Feb15].

### Ranks, names, stars per rank

Star counts were read from the star-icon cells of the [GP-Feb15] table (identical names in [GP-Jul14]); bands confirmed by [WGG-old] ("higher ranks used 4 or 5 stars").

| Rank | Name | Stars | | Rank | Name | Stars |
|---|---|---|---|---|---|---|
| 25 | Angry Chicken | 2 | | 12 | Warsong Commander | 4 |
| 24 | Leper Gnome | 2 | | 11 | Big Game Hunter | 4 |
| 23 | Argent Squire | 2 | | 10 | Ogre Magi | 5 |
| 22 | Murloc Raider | 2 | | 9 | Silver Hand Knight | 5 |
| 21 | Southsea Deckhand | 2 | | 8 | Frostwolf Warlord | 5 |
| 20 | Shieldbearer | 3 | | 7 | Sunwalker | 5 |
| 19 | Novice Engineer | 3 | | 6 | Ancient of War | 5 |
| 18 | Sorcerer's Apprentice | 3 | | 5 | Sea Giant | 5 |
| 17 | Tauren Warrior | 3 | | 4 | Mountain Giant | 5 |
| 16 | Questing Adventurer | 3 | | 3 | Molten Giant | 5 |
| 15 | Silvermoon Guardian | 4 | | 2 | The Black Knight | 5 |
| 14 | Raid Leader | 4 | | 1 | Innkeeper | 5 |
| 13 | Dread Corsair | 4 | | 0 | Legend | none |

Bands: **25-21 = 2 stars, 20-16 = 3, 15-11 = 4, 10-1 = 5**. Total stars from 25/0 to Legend = 5x2 + 5x3 + 5x4 + 10x5 = **95**.

Rank 25 starts with **0 stars** (changed from 1 in Patch 1.0.0.4944, 2014-03-11) [WGG].

Star mechanics [GP-Jul14]: win = +1 star; filling all slots and winning again puts you on the next rank with 1 star. "Any given rank with full stars is equal in value to the next rank up with no stars." Losing at X/0 drops you to the previous rank with (max-1) stars. Overflow (incl. bonus star) carries into the next rank (e.g. rank 25 at 2/2 + win with streak -> rank 24 at 2/2).

### Win-streak bonus stars

- "Grants players a bonus star if they also won the previous two ranked matches (up to Rank 5)" -> i.e. the 3rd, 4th, 5th... consecutive win gives 2 stars [GP-Jul14]. Streaks persist across sessions [GP-Jul14].
- Applies at **ranks 25-6**; "Winning streak bonus stars stop being awarded at Rank 5 and higher" [WGG-old]. A bonus earned at rank 6 can carry you into rank 5 [WGG-old].
- No lose-streak penalty existed [GP-Jul14].
- Introduced in Patch 1.0.0.4217 (2013-12-10) [GP-Jul14 History], [WGG-old].

### Losing stars / floors

- **Ranks 25-21: losses cost nothing** (no star loss). From **rank 20 up to rank 1** each loss = -1 star (can drop ranks) [GP-Jul14]: "Above Rank 21, losing games will also cause players to lose stars... once Rank 20 has been achieved, the player will be unable to drop below this rank, with games lost at Rank 20 and no stars having no effect".
- So in 2014 the only floors were **Rank 20** (effectively) and **Legend** ("Once a player has attained Legend rank, the rank cannot be lost until the season ends") [GP-Jul14]; [WGG-old]: "Rank 20 and Legend floors existed before Patch 7.1.0.17720".
- Floors at **15, 10, 5** were added in **Patch 7.1.0.17720, 2017-02-28** ("The milestones are Rank 20, 15, 10, 5, and Legend") [WGG]. Your belief is correct: not in 2014.

### Legend

- Rank above 1; cannot be lost within the season [GP-Jul14].
- Players in the **top 10,000** of their region see their exact regional position number in the medal (e.g. "425" = 425th) [GP-Jul14]; since Patch 1.0.0.4217 [WGG]. Below top 10,000: plain Legend medal, no number (implied by [GP-Jul14]; *not explicitly stated what is shown - mark uncertain*).

### Season reset (monthly)

- Seasons = calendar months; Season 1 "Pandamonium" = 1-30 April 2014; test seasons Dec 2013 - Mar 2014. Ends 11:59 PM PST (Americas) / CET (EU) [GP-Feb15].
- Reset rule (Patch 1.0.0.4944, 2014-03-11, valid until early 2018): everybody goes to Rank 25 with 0 stars and receives **1 bonus star per rank above 25 held at season end** = (25 - endRank) stars, Legend counts as 0 -> 25 stars [GP-Jul14], [WGG-old].
- Examples [GP-Jul14]: end 15 -> 10 stars -> Rank 21 with 2 stars; end 20 -> Rank 23, 1 star; end 10 -> Rank 19, 2 stars; end 5 -> Rank 17, 1 star; end 1 -> Rank 16, 2 stars; **Legend -> Rank 16 with 3 stars (max)**.
- Note: "rank at end of season" is the end rank, not best rank (GP wording). [WGG-old] paraphrases "their best rank" for pre-2018 - *minor uncertainty; GP 2014 text says end-of-season rank*.
- Before 1.0.0.4944 (beta, Dec 2013-Mar 2014) the reset was a hard reset to Rank 25 [GP-Jul14 History].
- Later changes (out of 2014 scope): March 2018 -> "4 ranks below highest standing"; all ranks 5 stars [WGG-old].

### Season rewards (2014)

- **Season card back** for reaching **Rank 20** at any point in the season, granted at season end; must log in during the season [GP-Jul14], introduced Patch 1.0.0.4944 [WGG]. "A maximum of 11 wins needed each season" (10 stars for 25-21 + 1 to reach 20; fewer with streaks) [GP-Feb15].
- **Golden hero** for **500 Ranked wins** with that hero (cumulative, not seasonal) [GP-Jul14].
- Legend: qualification points for the 2014/2015 World Championship [GP-Feb15].
- No end-of-season chest in 2014 (chest added Patch 3.0.0.9786, 2015-08-18) [WGG-old].
- Gold: shared Play-mode reward of 10 gold per 3 wins, max 100 gold/day (Ranked and Casual alike) [GP-Jul14].

### Hidden MMR & matchmaking

- Ranks 25-1: matched **by rank and number of stars**, not MMR. Blizzard CM Aratil, 2014-01-21: "before a player hits Legend rank, matchmaking actually uses the amount of stars that a player has to determine opponents. Only players in Legend rank are matched using MMR." [BLUE-Aratil]
- Legend: matched by a **hidden Ranked MMR** [BLUE-Aratil], [GP-Jul14]. Aratil (Jan 2014): Ranked MMR **resets each season**; Casual MMR does not [BLUE-Aratil]. ([WGG-old] says MMR is tracked throughout Ranked and also seeds the initial Legend number - that is later knowledge, *uncertain whether it applied in 2014*.)
- Legend players were often matched vs sub-Legend players; mechanism never officially explained [GP-Jul14].
- Ranked MMR and Casual MMR were separate (confirmed at 1.0.0.4217) [GP-Jul14 History].
- Rank-based matchmaking for 25-1 lasted until Patch 17.0.0.44222 (2020-04-01) [WGG-old].

### Casual mode

- Unranked play, same constructed decks, no rank change. "Matchmaking in Casual mode is determined by each player's Casual matchmaking rating (MMR)... There is currently no scheduled reset for Casual MMRs, but they are designed to change quickly in response to win and lose streaks." [GP-Jul14], citing [BRODE-Casual].
- Counts toward quests and the 10 gold / 3 wins reward; does not count for golden heroes (those need Ranked wins) [GP-Jul14].

### Rank distribution (Blizzard, Sept 2014, seasons 1-5) [GP-Feb15]

25-15: 75%; 15-10: 17.5%; 10-5: 5.5%; 5-Legend: 2%; Legend: 0.5%.

---

## ARENA (2014)

All from [GP-Arena-Oct14] unless noted.

- **Entry**: 150 gold or real money ($1.99 / EUR 1.79 / GBP 1.49 / R$4.50 / 66 RUB). *Uncertain/not covered*: free first run for new players (later versions gave one; not verified for 2014).
- **Draft**: pick 1 of 3 random classes; then 30 picks, each 1 of 3 cards of the same rarity ("sets may offer three common cards, or three legendary cards"); only neutral + chosen class cards; no copy limit (incl. legendaries).
- **Run end**: "Once a player has lost 3 times, or won 12 times, their run will end." Can retire anytime (reward based on wins so far). Max 14 games. Runs can be paused and continued later. Disconnect = loss.
- **Matchmaking**: "determined by the player's win/loss record for the current run, attempting to find a player with as similar a record as possible" (cites [ZERI]). [WGG-Arena] confirms record-based pairing as current rule; the April 2016 "new players matched as if they had one more loss" tweak is post-2014.
- **Rewards** (key per win count, Novice 0 ... Lightforge 12): always 1 expert pack; 0-2 wins: pack + 1 random (gold/dust/common); 3-6 wins: 3 rewards incl. guaranteed gold (25-35 at 3 wins up to 75-85 at 6); 7+ wins: guaranteed gold 150-160 (7-9 wins), 170-185 (10), 195-210 (11), 215-235 (12), i.e. 7 wins refunds the entry; 12 wins = 5 rewards. Top keys can give golden cards; top three keys never give non-golden commons. Values are community-collected ranges (*approximate*). Rewards depend only on wins of the current run.
- Key names: Novice, Apprentice, Journeyman, Copper, Silver, Gold, Platinum, Diamond, Champion, Ruby, Frostborn, Molten, Lightforge.
- Win distribution (if 50/50 matching): 50% of players reach 3+ wins; 12 wins ~0.65%.
