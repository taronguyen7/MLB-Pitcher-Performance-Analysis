-- Checkpoint
SELECT *
FROM savant_data_mysql;

-- Create a working table with only the fields needed for the pitcher analysis
-- and filter to the six selected starting pitchers
CREATE TABLE pitcher_data AS
SELECT
    player_name,
    game_pk,
    inning,
    events,
    description,
    release_speed,
    pitch_type,
    launch_speed
FROM savant_data_mysql
WHERE player_name IN (
    'Sanchez, Christopher',
    'Yamamoto, Yoshinobu', 
    'Crochet, Garrett',
    'Skubal, Tarik',
    'Brown, Hunter',
    'Skenes, Paul'
);

-- Checkpoint
SELECT *
FROM pitcher_data;

-- Add game stage column
ALTER TABLE pitcher_data
ADD COLUMN game_stage VARCHAR(10);

-- Convert names from "Last, First" to "First Last"
UPDATE pitcher_data
SET player_name = CONCAT(
    TRIM(SUBSTRING_INDEX(player_name, ',', -1)),
    ' ',
    TRIM(SUBSTRING_INDEX(player_name, ',', 1))
)
WHERE player_name LIKE '%,%';

-- Classify pitches by game stage
UPDATE pitcher_data
SET game_stage =
    CASE
        WHEN inning BETWEEN 1 AND 3 THEN 'Early'
        WHEN inning BETWEEN 4 AND 6 THEN 'Middle'
        WHEN inning >= 7 THEN 'Late'
    END;

-- Standardize Cristopher Sanchez's first name
UPDATE pitcher_data
SET player_name = 'Cristopher Sanchez'
WHERE player_name = 'Christopher Sanchez';

-- Create master summary view with all pitcher-stage metrics
CREATE OR REPLACE VIEW pitcher_stage_summary AS
WITH pitcher_stats AS
(
    SELECT
        player_name,
        game_stage,

        -- Hits
        SUM(CASE 
            WHEN events IN ('single', 'double', 'triple', 'home_run')
            THEN 1
            ELSE 0
        END) AS hits,

        -- At-bats
        SUM(CASE 
            WHEN events NOT IN (
                'walk',
                'hit_by_pitch',
                'sac_bunt',
                'sac_fly',
                'catcher_interf',
                'truncated_pa',
                ''
            )
            THEN 1
            ELSE 0
        END) AS at_bats,

        -- Average primary fastball velocity
        ROUND(
            AVG(CASE
                WHEN player_name = 'Cristopher Sanchez' AND pitch_type = 'SI'
                THEN release_speed
                WHEN player_name != 'Cristopher Sanchez' AND pitch_type = 'FF'
                THEN release_speed
            END),
            1
        ) AS avg_primary_fastball_velo,

        -- Whiffs
        SUM(CASE
            WHEN description IN (
                'swinging_strike',
                'swinging_strike_blocked',
                'missed_bunt'
            )
            THEN 1
            ELSE 0
        END) AS whiffs,

        -- Total swings
        SUM(CASE
            WHEN description IN (
                'swinging_strike',
                'swinging_strike_blocked',
                'hit_into_play',
                'foul',
                'foul_tip',
                'missed_bunt',
                'bunt_foul_tip',
                'foul_bunt'
            )
            THEN 1
            ELSE 0
        END) AS total_swings,

        -- Strikeouts
        SUM(CASE
            WHEN events IN ('strikeout', 'strikeout_double_play')
            THEN 1
            ELSE 0
        END) AS strikeouts,

        -- Plate appearances
        SUM(CASE
            WHEN events NOT IN ('', 'truncated_pa')
            THEN 1
            ELSE 0
        END) AS plate_appearances,

        -- Walks
        SUM(CASE
            WHEN events = 'walk'
            THEN 1
            ELSE 0
        END) AS walks,

        -- Hard-hit balls
        SUM(CASE
            WHEN description = 'hit_into_play'
            AND CAST(launch_speed AS DECIMAL(5,1)) >= 95
            THEN 1
            ELSE 0
        END) AS hard_hits,

        -- Batted balls
        SUM(CASE
            WHEN description = 'hit_into_play'
            AND launch_speed != ''
            THEN 1
            ELSE 0
        END) AS batted_balls

    FROM pitcher_data
    GROUP BY player_name, game_stage
)

SELECT
    player_name,
    game_stage,
    hits,
    at_bats,

    CASE
        WHEN game_stage = 'Early' THEN 1
        WHEN game_stage = 'Middle' THEN 2
        WHEN game_stage = 'Late' THEN 3
    END AS stage_order,

    -- BAA
    ROUND(hits / at_bats, 3) AS BAA,

    avg_primary_fastball_velo,

    -- Whiff rate
    ROUND(whiffs / total_swings, 4) AS whiff_rate,

    -- Strikeout rate
    ROUND(strikeouts / plate_appearances, 4) AS k_rate,

    -- Walk rate
    ROUND(walks / plate_appearances, 4) AS bb_rate,

    -- Hard-hit rate
    ROUND(hard_hits / batted_balls, 4) AS hard_hit_rate

FROM pitcher_stats;
