/* -- CBAS kode fra produktionen version 4 fra Christian 2024  */
USE RAR_PROJEKT;
GO

DROP TABLE IF EXISTS #Person;
SELECT 
   *
  ,NULL AS TJNR_MATCH 
  ,NULL AS CPR_INST_MATCH
  ,NULL AS CPR_MATCH
INTO #Person
FROM RAR_PROJEKT.WH.WH_SD_PERSON pers
WHERE 1 = 1
  AND CONVERT(date, GETDATE()) BETWEEN START AND SLUT
  AND INST NOT IN ('2P', 'ZZ');

 /* -- CBAS LeveranceDato er tilføjet af Søren 23.09.2024 */
DROP TABLE IF EXISTS #CBAS;
SELECT 
   *
  ,ROW_NUMBER() OVER(ORDER BY BRUGERNAVN) AS CBAS_ID 
  ,CPRNR AS CPR
  ,LeveranceDato as LeveranceDato_CBAS
  ,COALESCE(CONCAT(LoenInstitutionskode, tjenestenr), 'UKENDT') AS TJNR
  ,CASE
    WHEN Firmakode = '1309' THEN 'BI'
    WHEN Firmakode = '1401' THEN 'Ukendt' 
    WHEN Firmakode = '1500' THEN 'PV' 
    WHEN Firmakode = 'AKUT' THEN '2J' 
    WHEN Firmakode = 'AMAG' THEN 'HV' 
    WHEN Firmakode = 'APOT' THEN 'BO' 
    WHEN Firmakode = 'BORN' THEN 'BH' 
    WHEN Firmakode = 'DSVI' THEN 'HC' 
    WHEN Firmakode = 'GENT' THEN 'HE'
    WHEN Firmakode = 'GLOS' THEN 'RH' 
    WHEN Firmakode = 'HERL' THEN 'HE' 
    WHEN Firmakode = 'HRUD' THEN '2F' 
    WHEN Firmakode = 'HVID' THEN 'HV' 
    WHEN Firmakode = 'IMTE' THEN '2F'
    WHEN Firmakode = 'NORD' THEN 'NH'
    WHEN Firmakode = 'RIGS' THEN 'RH'
    WHEN Firmakode = 'SDCC' THEN '2S'
    WHEN Firmakode = 'STAB' THEN '2F'
    ELSE 'Ukendt'
   END AS FIRMAKODE_INST
INTO #CBAS
FROM RAR_PROJEKT.PSA.PSA_CBAS;

/* -- Først matches på tjnr - hvis der er et match er dette altid et 1:1-match */
UPDATE #Person
SET TJNR_MATCH = cbas.CBAS_ID
FROM #Person pers
LEFT JOIN #CBAS cbas ON cbas.TJNR = pers.TJNR;

/* -- Herefter matches på CPR OG institution - en række med en mail foretrækkes over en række uden en mail */
WITH RankedInst AS
(
  SELECT 
     *
    ,ROW_NUMBER() OVER(PARTITION BY CPR, FIRMAKODE_INST ORDER BY CASE WHEN EMAIL IS NOT NULL THEN 1 ELSE NULL END DESC, BRUGER_UPDATEDDATETIME DESC) AS RN
  FROM #CBAS
)
UPDATE #Person
SET CPR_INST_MATCH = cbas.CBAS_ID
FROM #Person pers
LEFT JOIN RankedInst cbas ON cbas.CPR = pers.CPR AND cbas.FIRMAKODE_INST = pers.INST AND cbas.RN = 1;

/* -- Til sidst matches kun på CPR - en række med en mail foretrækkes over en række uden en mail ligesom før */
WITH RankedInst AS
(
  SELECT 
     *
    ,ROW_NUMBER() OVER(PARTITION BY CPR ORDER BY CASE WHEN EMAIL IS NOT NULL THEN 1 ELSE NULL END DESC, BRUGER_UPDATEDDATETIME DESC) AS RN
  FROM #CBAS
)
UPDATE #Person
SET CPR_MATCH = cbas.CBAS_ID
FROM #Person pers
LEFT JOIN RankedInst cbas ON cbas.CPR = pers.CPR AND cbas.RN = 1;

/* -- I den endelige tabel vises kun ét gæt på brugernavn og email, samt en markering af hvordan gættet er fremkommet */
DROP TABLE IF EXISTS #Output;
SELECT
   src.INST
  ,src.TJNR
  ,src.CPR
  ,src.NAVN
  ,src.STAT
  ,src.MATCH_INFO
  ,cbas.BRUGERNAVN
  ,cbas.EMAIL
  ,cbas.LeveranceDato_CBAS
INTO #Output
FROM
(
  SELECT
     *
    ,CASE
      WHEN TJNR_MATCH IS NOT NULL THEN 'Match på tjenestenummer'
      WHEN CPR_INST_MATCH IS NOT NULL THEN 'Match på CPR-nummer og institution'
      WHEN CPR_MATCH IS NOT NULL THEN 'Match på CPR-nummer'
      ELSE 'Intet match'
     END AS MATCH_INFO
    ,COALESCE(TJNR_MATCH, CPR_INST_MATCH, CPR_MATCH) AS CBAS_ID
  FROM #Person
) src
LEFT JOIN #CBAS cbas ON cbas.CBAS_ID = src.CBAS_ID;

/* -- I den endelige tabel vises kun ét gæt på brugernavn og email, samt en markering af hvordan gættet er fremkommet */
SELECT *
	FROM #Output;


/* -- I tabellen til LON_HR sættes SOR plus opdateringsdato på tabellen Søren 23.09.2024  */

DROP TABLE IF EXISTS LON_HR.SD.SD_CBAS_MATCH;

SELECT 
CBAS_EMAILINFO.INST,
CBAS_EMAILINFO.TJNR,
CBAS_EMAILINFO.CPR,
CBAS_EMAILINFO.STAT,
CBAS_EMAILINFO.NAVN,
CBAS_EMAILINFO.MATCH_INFO,
CBAS_EMAILINFO.BRUGERNAVN,
CBAS_EMAILINFO.EMAIL,
/* -- Current_row_activ_employment */
CASE
	WHEN CBAS_EMAILINFO.STAT='1' or CBAS_EMAILINFO.STAT='3' THEN 1
	ELSE 0
END AS Current_row_activ_employment,

INST_SOR.SOR,
CBAS_EMAILINFO.LeveranceDato_CBAS,
CONVERT(datetime2 (0), GETDATE()) AS Opdateringsdato 
	   INTO LON_HR.SD.SD_CBAS_MATCH
		  FROM #Output CBAS_EMAILINFO
			LEFT JOIN RAR_PROJEKT.WH.Hospitalsforkortelse_SOR  INST_SOR 
				ON CBAS_EMAILINFO.INST = INST_SOR.Hospitalsforkortelse    
					WHERE 1 = 1;

/* -- Viser os outputtet fra SD_CBAS_EMAILINFO_NEWBETA */
/*
SELECT *
	FROM LON_HR.SD.SD_CBAS_EMAILINFO_NEWBETA;
*/