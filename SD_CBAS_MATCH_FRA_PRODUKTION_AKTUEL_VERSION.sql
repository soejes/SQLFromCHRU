/* Version fra 19.11.2024 */


USE RAR_PROJEKT
GO

-- Outputformat
DROP TABLE IF EXISTS LON_HR.SD.SD_CBAS_MATCH;
CREATE TABLE LON_HR.SD.SD_CBAS_MATCH (
   INST                           varchar(2)
  ,TJNR                           varchar(7)
  ,CPR                            varchar(10)
  ,NAVN                           varchar(100)
  ,STAT                           varchar(1)
  ,MATCH_INFO                     varchar(100)
  ,BRUGERNAVN                     varchar(100)
  ,EMAIL                          varchar(100)
  ,CURRENT_ROW_ACTIV_EMPLOYMENT   int
  ,SOR                            varchar(20)
  ,LEVERANCEDATO_CBAS             date
  ,OPDATERINGSDATO                datetime2
);

-- Person
DROP TABLE IF EXISTS #Person;
SELECT *
INTO #Person
FROM RAR_PROJEKT.WH.WH_SD_PERSON
WHERE 1 = 1
  AND CONVERT(date, GETDATE()) BETWEEN [START] AND SLUT
  AND INST NOT IN ('2P', 'ZZ');

-- CBAS
DROP TABLE IF EXISTS #CBAS;
SELECT 
   *
  ,ROW_NUMBER() OVER(ORDER BY BRUGERNAVN) AS CBAS_ID 
  ,CPRNR AS CPR
  ,COALESCE(CONCAT(LoenInstitutionskode, tjenestenr), 'UKENDT') AS TJNR
  ,CASE WHEN email IS NULL THEN 0 ELSE 1 END AS HAR_EMAIL
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

-- Matches
INSERT INTO LON_HR.SD.SD_CBAS_MATCH
SELECT 
   src.INST
  ,src.TJNR
  ,src.CPR
  ,src.NAVN
  ,src.STAT
  ,NULL AS MATCH_INFO
  ,(  SELECT TOP 1 CBAS_ID
      FROM #CBAS cbas
      WHERE cbas.CPR = src.CPR
      ORDER BY
         CASE WHEN cbas.TJNR = src.TJNR THEN 1 ELSE 0 END DESC
        ,CASE WHEN cbas.FIRMAKODE_INST = src.INST THEN 1 ELSE 0 END DESC
        ,cbas.Person_UpdatedDatetime DESC
   ) AS BRUGERNAVN
  ,(  SELECT TOP 1 CBAS_ID
      FROM #CBAS cbas
      WHERE cbas.CPR = src.CPR
      ORDER BY
         cbas.HAR_EMAIL DESC
        ,CASE WHEN cbas.TJNR = src.TJNR THEN 1 ELSE 0 END DESC
        ,CASE WHEN cbas.FIRMAKODE_INST = src.INST THEN 1 ELSE 0 END DESC
        ,cbas.Person_UpdatedDatetime DESC
   ) AS EMAIL
  ,CASE WHEN STAT IN ('1', '3') THEN 1 ELSE 0 END AS CURRENT_ROW_ACTIV_EMPLOYMENT
  ,sor.SOR
  ,(SELECT MAX(LEVERANCEDATO) FROM #CBAS) AS LEVERANCEDATO_CBAS
  ,GETDATE() AS OPDATERINGSDATO
FROM #Person src
LEFT JOIN RAR_PROJEKT.WH.Hospitalsforkortelse_SOR sor ON sor.Hospitalsforkortelse = src.INST;

-- Match-info
UPDATE LON_HR.SD.SD_CBAS_MATCH
SET 
   MATCH_INFO = CASE WHEN cbas_brugernavn.CPR IS NULL THEN 'Intet match' ELSE CONCAT(
    'Brugernavn: ',
    CASE 
      WHEN cbas_brugernavn.TJNR = src.TJNR THEN 'Tjnr'
      WHEN cbas_brugernavn.FIRMAKODE_INST = src.INST THEN 'CPR og inst'
      WHEN cbas_brugernavn.CPR = src.CPR THEN 'Kun CPR'
      ELSE 'Intet match'
    END,
    ' / Mail: ',
    CASE 
      WHEN cbas_email.TJNR = src.TJNR THEN 'Tjnr'
      WHEN cbas_email.FIRMAKODE_INST = src.INST THEN 'CPR og inst'
      WHEN cbas_email.CPR = src.CPR THEN 'Kun CPR'
      ELSE 'Intet match'
    END
   ) END
  ,BRUGERNAVN = cbas_brugernavn.BRUGERNAVN
  ,EMAIL = cbas_email.EMAIL
FROM LON_HR.SD.SD_CBAS_MATCH src
LEFT JOIN #CBAS cbas_brugernavn ON cbas_brugernavn.CBAS_ID = src.BRUGERNAVN
LEFT JOIN #CBAS cbas_email ON cbas_email.CBAS_ID = src.EMAIL;

SELECT *
FROM LON_HR.SD.SD_CBAS_MATCH;