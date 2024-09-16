WITH
input AS (
    SELECT REPLACE(REPLACE(
    '&str', ' ', ''), '.', ',') str
    FROM dual
),
input1 AS (
    SELECT 
    REGEXP_REPLACE(
    REGEXP_REPLACE(str, '(\()(\w)', '\1+\2'),
    '([+-]((\d+(,\d+)?)?x(\^\d+)?|\d+(,\d+)?))', '+(\1)')str
    FROM (
        SELECT CASE 
            WHEN REGEXP_LIKE(str, '^[+-]') 
            THEN REGEXP_REPLACE(str, '([^+-])\(', '\1+(')
            ELSE '+'||REGEXP_REPLACE(str, '([^+-])\(', '\1+(') 
            END str
        FROM input
    )
),
processed_input AS (
    SELECT 
    REGEXP_REPLACE(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(str, 
                        '([+-])(x)', '\11\2'),
                    '([+-])(\d+(,\d+)?)([^[:digit:]x,])', '\1\2x^0\4'),
                '([+-])(\d+(,\d+)?x)([^\^])', '\1\2^1\4'),
            '([+-])(x)', '\11\2'),
        '([+-])(\d+(,\d+)?)([^[:digit:]x,])', '\1\2x^0\4'),
    '([+-])(\d+(,\d+)?x)([^\^])', '\1\2^1\4') str
    FROM input1
),
a AS (
    SELECT REGEXP_SUBSTR(str, '[\(\)+-]|(\d+(,\d+)?x\^\d+)', 1, LEVEL) col, 
        ROWNUM r
    FROM processed_input
    CONNECT BY LEVEL <= LENGTH (str)
    AND REGEXP_SUBSTR(str, 
    '[\(\)+-]|(\d+(,\d+)?x\^\d+)', 1, LEVEL) IS NOT NULL
),
b AS (
    SELECT col, r, CASE 
        WHEN col = '(' THEN (SELECT col FROM a a1 WHERE a1.r=a.r-1)
        WHEN col = ')' THEN '?'
        END col1
    FROM a
),
numbers(det, r) AS (
    SELECT 
        CASE 
        WHEN (SELECT col FROM b WHERE r=2)='(' THEN ''
        ELSE (SELECT col FROM b WHERE r=1)
        END det, 1 r
    FROM dual
    UNION ALL
    SELECT 
    DECODE (
        col1, NULL, det, '?', 
        SUBSTR(NVL(det, RPAD(' ',20,' ')),1,LENGTH(det)-1),
        det||col1
    ) det, 
        numbers.r+1 r
    FROM numbers, b
    WHERE numbers.r <= (SELECT MAX(r) FROM b)
        AND numbers.r = b.r
),
c AS (
    SELECT CASE 
        WHEN REGEXP_LIKE(col, '[\(\)]') OR REGEXP_LIKE(col, '[+-]') 
            AND det IS NULL THEN NULL
        WHEN REGEXP_LIKE(col, '[+-]') THEN det||col
        ELSE col
        END col, 
        det
    FROM numbers NATURAL JOIN b
),
cwb AS (
    SELECT col, CASE 
        WHEN REGEXP_LIKE(col, '\w.*')
            THEN r-1
        ELSE NULL
        END col_extra, r
    FROM (
        SELECT col, ROWNUM r
        FROM c
        WHERE col IS NOT NULL
    )
),
cwb1 AS (
    SELECT CASE 
        WHEN REGEXP_LIKE(col, '\w.*') 
        THEN (CASE
            WHEN REGEXP_LIKE((SELECT col FROM cwb c1 
            WHERE c1.r=c2.col_extra), '^[+-].*')
            THEN (SELECT col FROM cwb c1 
            WHERE c1.r=c2.col_extra)
            ELSE '+'
            END)||col
        ELSE NULL
        END col
    FROM cwb c2
),
swb AS (
    SELECT REPLACE(SYS_CONNECT_BY_PATH(col,'&'),'&','') str
    FROM (SELECT col, rownum r FROM cwb1)
    WHERE r = (SELECT COUNT(*) FROM cwb1)
    START WITH r=1
    CONNECT BY PRIOR r=(r-1)
),
args AS (
    SELECT REGEXP_SUBSTR(str, '[+-]+\d+(,\d+)?x\^\d+', 1, LEVEL) col, 
        ROWNUM r
    FROM swb
    CONNECT BY LEVEL <= LENGTH (str)
    AND REGEXP_SUBSTR(str, '[+-]+\d+(,\d+)?x\^\d+', 1, LEVEL) IS NOT NULL
),
dec AS (
    SELECT col,
        REGEXP_SUBSTR(col, '[+-]+') sign, 
        RTRIM(REGEXP_SUBSTR(col, '\d+(,\d+)?x'), 'x') coef, 
        LTRIM(REGEXP_SUBSTR(col, '\^\d+'), '^') degree
    FROM args
),
dec1 AS (
    SELECT TO_NUMBER((CASE
        WHEN MOD(REGEXP_COUNT(sign, '-'), 2) = 1 THEN '-'
        ELSE '+' END)||TO_CHAR(coef)) sign_coef, degree
    FROM dec
),
dec2 AS (
    SELECT SUM (sign_coef) coef, degree
    FROM dec1
    GROUP BY degree
    ORDER BY degree DESC
),
res AS (
    SELECT REPLACE(SYS_CONNECT_BY_PATH(coef||'x^'||degree,'|'),'|','') str
    FROM (
        SELECT CASE 
            WHEN coef < 0 THEN TO_CHAR(coef)
            ELSE '+'||TO_CHAR(coef) 
            END coef, degree, rownum r 
        FROM dec2
    )
    WHERE r = (SELECT COUNT(*) FROM dec2)
    START WITH r=1
    CONNECT BY PRIOR r=(r-1)
)
SELECT REPLACE(inp.str, ',', '.') expression,
    NVL(REPLACE(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(res.str, 
                        '[+-]0x\^(\d)+', ''),
                    'x\^0$', ''),
                '(x)\^1([+-]|)', '\1\2'),
            '([^\d,])1(x)', '\1\2'),
        '^\+', ''),
    ',', '.'), '0')
    result
FROM res, input inp;
