/*
  MySQL                                 MSSQL Server 
  ------------------------------------- -------------------------------------- 
+ bpsa_v_source_code_pe_code         -- bpsa_v_source_code_pe_code
+ nsa_v_all_pc_ref_grouped           -- nsa_v_all_pc_ref_grouped
+ nsa_v_all_pc_to_pe                 -- nsa_v_all_pc_to_pe  
+ nsa_v_all_product_code_source_code -- nsa_v_all_product_code_source_code
+ nsa_v_all_product_codes            -- nsa_v_all_product_codes
+ nsa_v_all_sc_pc_ref_grouped        -- nsa_v_all_sc_pc_ref_grouped
+ nsa_v_all_sc_ref_grouped           -- nsa_v_all_sc_ref_grouped
+ nsa_v_all_sc_ref_grouped_1         -- nsa_v_all_sc_ref_grouped_1
+ nsa_v_all_sc_ref_grouped_2         -- nsa_v_all_sc_ref_grouped_2
+ nsa_v_all_source_codes             -- nsa_v_all_source_codes
+ nsa_v_feed_content_collection      -- nsa_v_feed_content_collection
+ nsa_v_feed_country                 -- nsa_v_feed_country
+ nsa_v_feed_industry                -- nsa_v_feed_industry
+ nsa_v_feed_region                  -- nsa_v_feed_region
+ nsa_v_feed_source_code             -- nsa_v_feed_source_code
+ nsa_v_feed_to_codes                -- nsa_v_feed_to_codes
+ nsa_v_feeds                        -- nsa_v_feeds (max for group)
+ nsa_v_mapped_source_code           -- nsa_v_mapped_source_code
+ nsa_v_mrn_pe_search                -- nsa_v_mrn_pe_search
+ nsa_v_news_map                     -- nsa_v_news_map
+ nsa_v_news_map_variant             -- nsa_v_news_map_variant (no regexp, no order)
+ nsa_v_not_covered_feeds            -- nsa_v_not_covered_feeds
+ rds_v_all_pc_pe                    -- rds_v_all_pc_pe
+ rds_v_pc_pe                        -- rds_v_pc_pe
+ tmp_nsa_v_feed_all_grouped         -- tmp_nsa_v_feed_all_grouped
+ ucdp_v_feed_to_sc                  -- ucdp_v_feed_to_sc
+ view_product_source_codes          -- view_product_source_codes
*/

-- =======================================================================================
-- 1. VIEW nsa_v_all_pc_ref_grouped
-- =======================================================================================
-- Should be checked because of using group_concat in MySql and different behaviour of Group By in MSSQL. 
-- In MySql we can select non aggregated columns without adding them to group by, 
-- but in MSSQL all non aggregated columns should be in group by or should be aggregated.
-- =======================================================================================
CREATE VIEW dbo.nsa_v_all_pc_ref_grouped AS
SELECT
    pc.product_code,
    pc.name,
    cc.content_collection,
    cc.content_collection_id,
    c.country,
    c.country_count,
    r.region,
    r.region_count,
    p.publication_type,
    p.pub_type_count,
    l.language,
    l.language_count,
    i.industry,
    i.industry_count,
    f.feed_count,
    pc.supplier_id,
    m.mrn_count,
    pc.consolidation_id
FROM dbo.t_all_product_code pc
LEFT JOIN dbo.t_content_collection cc
    ON pc.content_collection_id = cc.content_collection_id
-- Countries aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.country, ', ')
            WITHIN GROUP (ORDER BY d.country) AS country,
        COUNT(*) AS country_count
    FROM (
        SELECT DISTINCT c.id, c.country
        FROM dbo.t_ref_data_relations rrc
        JOIN dbo.t_ref_country c
            ON rrc.ref_id = c.id
           AND c.consolidation_id = pc.consolidation_id
        WHERE rrc.code_type = 'NP'
          AND rrc.ref_type = 'COUNTRY'
          AND rrc.code = pc.product_code
          AND rrc.consolidation_id = pc.consolidation_id
    ) d
) c
-- Regions aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.region, ', ')
            WITHIN GROUP (ORDER BY d.region) AS region,
        COUNT(*) AS region_count
    FROM (
        SELECT DISTINCT r.id, r.region
        FROM dbo.t_ref_data_relations rrr
        JOIN dbo.t_ref_region r
            ON rrr.ref_id = r.id
           AND r.consolidation_id = pc.consolidation_id
        WHERE rrr.code_type = 'NP'
          AND rrr.ref_type = 'REGION'
          AND rrr.code = pc.product_code
          AND rrr.consolidation_id = pc.consolidation_id
    ) d
) r
-- Publication types aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.publication_type, ', ')
            WITHIN GROUP (ORDER BY d.publication_type) AS publication_type,
        COUNT(*) AS pub_type_count
    FROM (
        SELECT DISTINCT p.id, p.publication_type
        FROM dbo.t_ref_data_relations rrp
        JOIN dbo.t_ref_publication_type p
            ON rrp.ref_id = p.id
           AND p.consolidation_id = pc.consolidation_id
        WHERE rrp.code_type = 'NP'
          AND rrp.ref_type = 'PUBLICATION'
          AND rrp.code = pc.product_code
          AND rrp.consolidation_id = pc.consolidation_id
    ) d
) p
-- Languages aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.language, ', ')
            WITHIN GROUP (ORDER BY d.language) AS language,
        COUNT(*) AS language_count
    FROM (
        SELECT DISTINCT l.id, l.language
        FROM dbo.t_ref_data_relations rrl
        JOIN dbo.t_ref_language l
            ON rrl.ref_id = l.id
           AND l.consolidation_id = pc.consolidation_id
        WHERE rrl.code_type = 'NP'
          AND rrl.ref_type = 'LANGUAGE'
          AND rrl.code = pc.product_code
          AND rrl.consolidation_id = pc.consolidation_id
    ) d
) l
-- Industries aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.industry, ', ')
            WITHIN GROUP (ORDER BY d.industry) AS industry,
        COUNT(*) AS industry_count
    FROM (
        SELECT DISTINCT i.id, i.industry
        FROM dbo.t_ref_data_relations rri
        JOIN dbo.t_ref_industry i
            ON rri.ref_id = i.id
           AND i.consolidation_id = pc.consolidation_id
        WHERE rri.code_type = 'NP'
          AND rri.ref_type = 'INDUSTRY'
          AND rri.code = pc.product_code
          AND rri.consolidation_id = pc.consolidation_id
    ) d
) i
-- Feed count
OUTER APPLY (
    SELECT COUNT(DISTINCT fdc.feed_code) AS feed_count
    FROM dbo.t_feed_product_code fdc
    WHERE fdc.product_code = pc.product_code
      AND fdc.consolidation_id = pc.consolidation_id
) f
-- MRN count
OUTER APPLY (
    SELECT COUNT(DISTINCT mpc.product_code) AS mrn_count
    FROM dbo.nsa_v_mrn_pe_pc mpc
    WHERE mpc.product_code = pc.product_code
) m;

-- =======================================================================================
-- 2. VIEW nsa_v_all_sc_ref_grouped_1
-- =======================================================================================
-- Should be checked because of using group_concat in MySql and different behaviour of Group By in MSSQL. 
-- In MySql we can select non aggregated columns without adding them to group by, 
-- but in MSSQL all non aggregated columns should be in group by or should be aggregated.
-- =======================================================================================
CREATE VIEW dbo.nsa_v_all_sc_ref_grouped_1 AS
SELECT
    sc.source_code,
    sc.name,
    cc.content_collection,
    cc.content_collection_id,
    sc.publisher,
    sc.url,
    c.country,
    c.country_count,
    r.region,
    r.region_count,
    p.publication_type,
    p.pub_type_count,
    j.provider,
    j.provider_count
FROM dbo.t_all_source_code sc
LEFT JOIN dbo.t_content_collection cc
    ON sc.content_collection_id = cc.content_collection_id
-- Countries aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.country, ', ')
            WITHIN GROUP (ORDER BY d.country) AS country,
        COUNT(*) AS country_count
    FROM (
        SELECT DISTINCT c.id, c.country
        FROM dbo.t_ref_data_relations rrc
        JOIN dbo.t_ref_country c
            ON rrc.ref_id = c.id
           AND c.consolidation_id = sc.consolidation_id
        WHERE rrc.code_type = 'NS'
          AND rrc.ref_type = 'COUNTRY'
          AND rrc.code = sc.source_code
          AND rrc.consolidation_id = sc.consolidation_id
    ) d
) c
-- Regions aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.region, ', ')
            WITHIN GROUP (ORDER BY d.region) AS region,
        COUNT(*) AS region_count
    FROM (
        SELECT DISTINCT r.id, r.region
        FROM dbo.t_ref_data_relations rrr
        JOIN dbo.t_ref_region r
            ON rrr.ref_id = r.id
           AND r.consolidation_id = sc.consolidation_id
        WHERE rrr.code_type = 'NS'
          AND rrr.ref_type = 'REGION'
          AND rrr.code = sc.source_code
          AND rrr.consolidation_id = sc.consolidation_id
    ) d
) r
-- Publication types aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.publication_type, ', ')
            WITHIN GROUP (ORDER BY d.publication_type) AS publication_type,
        COUNT(*) AS pub_type_count
    FROM (
        SELECT DISTINCT p.id, p.publication_type
        FROM dbo.t_ref_data_relations rrp
        JOIN dbo.t_ref_publication_type p
            ON rrp.ref_id = p.id
           AND p.consolidation_id = sc.consolidation_id
        WHERE rrp.code_type = 'NS'
          AND rrp.ref_type = 'PUBLICATION'
          AND rrp.code = sc.source_code
          AND rrp.consolidation_id = sc.consolidation_id
    ) d
) p
-- Provider aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.provider, '; ')
            WITHIN GROUP (ORDER BY d.provider) AS provider,
        COUNT(*) AS provider_count
    FROM (
        SELECT DISTINCT j.provider
        FROM dbo.t_all_sc_journalCode j
        WHERE j.source_code = REPLACE(sc.source_code, 'NS:', '')
    ) d
) j
WHERE sc.consolidation_id = (
    SELECT MAX(consolidation_id)
    FROM dbo.t_all_source_code
);

-- =======================================================================================
-- 3. VIEW nsa_v_all_sc_ref_grouped_2
-- =======================================================================================
-- Should be checked because of using group_concat in MySql and different behaviour of Group By in MSSQL. 
-- In MySql we can select non aggregated columns without adding them to group by, 
-- but in MSSQL all non aggregated columns should be in group by or should be aggregated.
-- =======================================================================================
CREATE VIEW dbo.nsa_v_all_sc_ref_grouped_2 AS
SELECT
    sc.source_code,
    l.language,
    l.language_count,
    i.industry,
    i.industry_count,
    n.translatedName,
    n.translatedName_count,
    sc.supplier_id,
    sc.status,
    f.feed_count,
    m.mrn_count,
    sc.consolidation_id
FROM dbo.t_all_source_code sc
-- Languages aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.language, ', ')
            WITHIN GROUP (ORDER BY d.language) AS language,
        COUNT(*) AS language_count
    FROM (
        SELECT DISTINCT l.id, l.language
        FROM dbo.t_ref_data_relations rrl
        JOIN dbo.t_ref_language l
            ON rrl.ref_id = l.id
           AND l.consolidation_id = sc.consolidation_id
        WHERE rrl.code_type = 'NS'
          AND rrl.ref_type = 'LANGUAGE'
          AND rrl.code = sc.source_code
          AND rrl.consolidation_id = sc.consolidation_id
    ) d
) l
-- Industry aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.industry, ', ')
            WITHIN GROUP (ORDER BY d.industry) AS industry,
        COUNT(*) AS industry_count
    FROM (
        SELECT DISTINCT i.id, i.industry
        FROM dbo.t_ref_data_relations rri
        JOIN dbo.t_ref_industry i
            ON rri.ref_id = i.id
           AND i.consolidation_id = sc.consolidation_id
        WHERE rri.code_type = 'NS'
          AND rri.ref_type = 'INDUSTRY'
          AND rri.code = sc.source_code
          AND rri.consolidation_id = sc.consolidation_id
    ) d
) i
-- Translated name aggregation
OUTER APPLY (
    SELECT
        STRING_AGG(d.translatedName, '; ')
            WITHIN GROUP (ORDER BY d.translatedName) AS translatedName,
        COUNT(*) AS translatedName_count
    FROM (
        SELECT DISTINCT 
            CONCAT(n.value, ' (', n.code, ')') AS translatedName,
            n.value
        FROM dbo.bpsa_reference_data n
        WHERE n.source_code = sc.source_code
          AND n.data_type = 'TRANSLATEDNAME'
          AND n.snapshot_id IN (
              SELECT s.snapshot_id
              FROM dbo.t_dm_in_data_snapshot s
              WHERE s.supplier_id = 'S:NR'
                AND s.data_type = 'ALL'
                AND s.latest = 'Y'
          )
    ) d
) n
-- Feed count
OUTER APPLY (
    SELECT COUNT(DISTINCT fsc.feed_code) AS feed_count
    FROM dbo.t_feed_source_code fsc
    WHERE fsc.source_code = sc.source_code
      AND fsc.consolidation_id = sc.consolidation_id
) f
-- MRN count
OUTER APPLY (
    SELECT COUNT(DISTINCT msc.pe_code) AS mrn_count
    FROM dbo.nsa_v_mrn_pe_sc msc
    WHERE msc.source_code = sc.source_code
) m
WHERE sc.consolidation_id = (
    SELECT MAX(consolidation_id)
    FROM dbo.t_all_source_code
);

-- =======================================================================================
-- 4. VIEW nsa_v_all_sc_ref_grouped
-- =======================================================================================
CREATE VIEW dbo.nsa_v_all_sc_ref_grouped AS
SELECT
    t1.source_code,
    t1.name,
    t1.content_collection,
    t1.content_collection_id,
    t1.publisher,
    t1.url,
    t1.country,
    t1.country_count,
    t1.region,
    t1.region_count,
    t1.publication_type,
    t1.pub_type_count,
    t1.provider,
    t1.provider_count,
    t2.language,
    t2.language_count,
    t2.industry,
    t2.industry_count,
    t2.translatedName,
    t2.translatedName_count,
    t2.supplier_id,
    t2.status,
    t2.feed_count,
    t2.mrn_count,
    t2.consolidation_id
FROM dbo.nsa_v_all_sc_ref_grouped_1 t1
JOIN dbo.nsa_v_all_sc_ref_grouped_2 t2
    ON t1.source_code = t2.source_code
WHERE t1.content_collection_id IS NOT NULL;

-- =======================================================================================
-- 5. VIEW nsa_v_all_sc_pc_ref_grouped
-- =======================================================================================
CREATE VIEW dbo.nsa_v_all_sc_pc_ref_grouped AS
SELECT DISTINCT
    pc.product_code AS code,
    pc.name AS name,
    pc.content_collection_id AS content_collection_id,
    pc.content_collection AS content_collection,
    pc.country AS country,
    pc.region AS region,
    pc.industry AS industry,
    'NP' AS code_type,
    pc.consolidation_id AS consolidation_id
FROM dbo.t_all_pc_ref_grouped pc
LEFT JOIN dbo.t_content_collection cc
    ON cc.content_collection = pc.content_collection
UNION
SELECT DISTINCT
    sc.source_code AS code,
    sc.name AS name,
    sc.content_collection_id AS content_collection_id,
    sc.content_collection AS content_collection,
    sc.country AS country,
    sc.region AS region,
    sc.industry AS industry,
    'NS' AS code_type,
    sc.consolidation_id AS consolidation_id
FROM dbo.t_all_sc_ref_grouped sc;

-- =======================================================================================
-- 6. VIEW nsa_v_news_map 
-- =======================================================================================
-- ORDER BY exists in MySQL version, but in MSSQL it is not possible to use ORDER BY in view, 
-- so it was removed. 
-- =======================================================================================
CREATE VIEW dbo.nsa_v_news_map AS
SELECT
    p.product_name AS product_name,
    REPLACE(p.product_code, 'NP:', '') AS product_code,
    pe.value AS pe_code,
    p.source_codes AS attribution_code,
    CASE
        WHEN pdppe.pe_code IS NOT NULL THEN 'Fee Liable'
        ELSE 'Included Where Indicated'
    END AS commercial_status,
    STRING_AGG(ISNULL(la.value, ''), ',')
        WITHIN GROUP (ORDER BY ISNULL(la.value, '')) AS language,
    p.product_code AS product_code_original
FROM dbo.rds_product_code p
INNER JOIN dbo.rds_reference_data pe
    ON pe.code = p.product_code
   AND pe.data_type = 'RUN_PE'
   AND pe.snapshot_id = p.snapshot_id
LEFT JOIN dbo.rds_reference_data la
    ON la.code = p.product_code
   AND la.data_type = 'LANGUAGE'
   AND la.snapshot_id = p.snapshot_id
LEFT JOIN dbo.t_ps2_pdp_pe pdppe
    ON pdppe.pe_code = pe.value
   AND EXISTS (
        SELECT 1
        FROM dbo.t_ps2_pdp pdp
        WHERE pdp.pdp_code = pdppe.pdp_code
          AND pdp.pdp_type = 'Specialist'
          AND pdp.snapshot_id = (
                SELECT s.snapshot_id
                FROM dbo.t_dm_in_data_snapshot s
                WHERE s.supplier_id = 'S:PS2'
                  AND s.data_type = 'PE_PDP'
                  AND s.latest = 'Y'
          )
   )
WHERE p.snapshot_id = (
        SELECT s.snapshot_id
        FROM dbo.t_dm_in_data_snapshot s
        WHERE s.supplier_id = 'S:RDS'
          AND s.data_type = 'RDS_PRODUCTS'
          AND s.latest = 'Y'
    )
  AND p.not_product_code = 0
  AND p.exclude_from_eikon = 0
GROUP BY
    pe.value,
    p.product_code,
    p.product_name,
    p.source_codes,
    pdppe.pe_code;

-- =======================================================================================
-- 7. VIEW nsa_v_feeds
-- =======================================================================================
-- In MySQL version there is group by only by feed_code and snapshot_id, 
-- but in MSSQL all non aggregated columns should be in group by or should be aggregated, 
-- so all columns are added to group by.
-- Also CONCAT_WS is replaced by CONCAT and NULLIF to avoid adding delimiters for null or empty values.
-- =======================================================================================
CREATE VIEW dbo.nsa_v_feeds AS
SELECT
    uf.feed_code,
    grp.isnative,
    grp.isinternal,
    grp.feedid,
    grp.visibility,
    grp.state,
    d.description,
    grp.copyrightOwner,
    p.parser,
    pd.parser_descr,
    o.onboarder,
    od.onboarder_descr,
    COUNT(uf.feed_index) AS feed_instance_count,
    uf.snapshot_id
FROM dbo.ucdp_v_feed uf
OUTER APPLY(
    SELECT TOP 1
        u2.isnative,
        u2.isinternal,
        u2.feedid,
        u2.visibility,
        u2.state,
        u2.copyrightOwner
    FROM dbo.ucdp_v_feed u2
    WHERE u2.feed_code = uf.feed_code
      AND u2.snapshot_id = uf.snapshot_id
    ORDER BY u2.feed_index DESC
) grp
OUTER APPLY(
    SELECT STRING_AGG(value, '|') WITHIN GROUP (ORDER BY value) AS description
    FROM(
        SELECT DISTINCT description AS value
        FROM dbo.ucdp_v_feed
        WHERE feed_code = uf.feed_code
          AND snapshot_id = uf.snapshot_id
    ) sub
) d
OUTER APPLY(
    SELECT STRING_AGG(value, '|') WITHIN GROUP (ORDER BY value) AS parser
    FROM(
        SELECT DISTINCT parser AS value
        FROM dbo.ucdp_v_feed
        WHERE feed_code = uf.feed_code
          AND snapshot_id = uf.snapshot_id
    ) sub
) p
OUTER APPLY(
    SELECT STRING_AGG(value, '|') WITHIN GROUP (ORDER BY value) AS parser_descr
    FROM(
        SELECT DISTINCT NULLIF(CONCAT_WS(' - ', parser, parser_descr), '') AS value
        FROM dbo.ucdp_v_feed
        WHERE feed_code = uf.feed_code
          AND snapshot_id = uf.snapshot_id
    ) sub
) pd
OUTER APPLY(
    SELECT STRING_AGG(value, '|') WITHIN GROUP (ORDER BY value) AS onboarder
    FROM(
        SELECT DISTINCT onboarder AS value
        FROM dbo.ucdp_v_feed
        WHERE feed_code = uf.feed_code
          AND snapshot_id = uf.snapshot_id
    ) sub
) o
OUTER APPLY(
    SELECT STRING_AGG(value, '|') WITHIN GROUP (ORDER BY value) AS onboarder_descr
    FROM(
        SELECT DISTINCT NULLIF(CONCAT_WS(' - ', onboarder, onboarder_descr), '') AS value
        FROM dbo.ucdp_v_feed
        WHERE feed_code = uf.feed_code
          AND snapshot_id = uf.snapshot_id
    ) sub
) od
GROUP BY
    uf.feed_code,
    uf.snapshot_id,
    d.description,
    p.parser,
    pd.parser_descr,
    o.onboarder,
    od.onboarder_descr,
    grp.isnative,
    grp.isinternal,
    grp.feedid,
    grp.visibility,
    grp.state,
    grp.copyrightOwner;

-- =======================================================================================
-- 8. VIEW nsa_v_news_map_variant
-- =======================================================================================
-- Function regexp_like used in MySQL version is not available in MSSQL, 
-- so the condition with like and OR can be used instead.
-- ORDER BY exists in MySQL version, but in MSSQL it is not possible to use ORDER BY in view,
-- so it was removed. 
-- =======================================================================================
CREATE VIEW dbo.nsa_v_news_map_variant AS
SELECT DISTINCT
    pdppe.pe_code,
    pdppe.pdp_code
FROM dbo.t_ps2_pdp_pe pdppe
JOIN dbo.t_ps2_pdp pdp
    ON pdp.pdp_code = pdppe.pdp_code
JOIN dbo.nsa_v_news_map v1
    ON v1.pe_code = pdppe.pe_code
WHERE pdppe.snapshot_id = (
        SELECT s.snapshot_id
        FROM dbo.t_dm_in_data_snapshot s
        WHERE s.supplier_id = 'S:PS2'
          AND s.data_type = 'PE_PDP'
          AND s.latest = 'Y'
      )
  AND pdp.snapshot_id = pdppe.snapshot_id
  AND (
        pdppe.pdp_code LIKE 'WWEIKON%'
        OR pdppe.pdp_code LIKE 'WWRFTW%'
        OR pdp.owner = 'LUCY CHAPLE'
      )
  AND EXISTS (
        SELECT 1
        FROM dbo.t_ps2_pli pli
        WHERE pli.product_status = 'RRG'
          AND pli.snapshot_id = (
                SELECT s.snapshot_id
                FROM dbo.t_dm_in_data_snapshot s
                WHERE s.supplier_id = 'S:PS2'
                  AND s.data_type = 'PE_PLI'
                  AND s.latest = 'Y'
          )
          -- regex-equivalent condition
          AND (
                ' ' + pli.permissioning_key + ' '
                LIKE '% ' + pdppe.pdp_code + ' %'
          )
    );

-- =======================================================================================
-- 9. VIEW nsa_v_feed_content_collection
-- =======================================================================================
CREATE VIEW dbo.nsa_v_feed_content_collection AS
SELECT DISTINCT
    f.feed_code,
    sc.content_collection_id,
    sc.consolidation_id
FROM dbo.t_mapped_source_code sc
JOIN dbo.ucdp_v_feed_to_sc usa
    ON sc.mnemonic = usa.source_code
JOIN dbo.t_feeds f
    ON usa.feed_code = f.feed_code
   AND sc.consolidation_id = f.consolidation_id;

-- =======================================================================================
-- 10. VIEW nsa_v_feed_country
-- =======================================================================================
CREATE VIEW dbo.nsa_v_feed_country AS
SELECT DISTINCT
    t.feed_code,
    v.id AS country_id,
    t.consolidation_id
FROM dbo.t_feed_codes t
JOIN dbo.nsa_v_code_country t1
    ON t.code = t1.code
   AND t.consolidation_id = t1.consolidation_id
JOIN dbo.t_ref_country v
    ON t1.country = v.country
   AND t.consolidation_id = v.consolidation_id;

-- =======================================================================================
-- 11. VIEW nsa_v_feed_industry
-- =======================================================================================
CREATE VIEW dbo.nsa_v_feed_industry AS
SELECT DISTINCT
    t.feed_code,
    v.id AS industry_id,
    t.consolidation_id
FROM dbo.t_feed_codes t
JOIN dbo.nsa_v_code_industry t1
    ON t.code = t1.code
   AND t.consolidation_id = t1.consolidation_id
JOIN dbo.t_ref_industry v
    ON t1.industry = v.industry
   AND t.consolidation_id = v.consolidation_id;

-- =======================================================================================
-- 12. VIEW nsa_v_feed_region
-- =======================================================================================
CREATE VIEW dbo.nsa_v_feed_region AS
SELECT DISTINCT
    t.feed_code,
    v.id AS region_id,
    t.consolidation_id
FROM dbo.t_feed_codes t
JOIN dbo.nsa_v_code_region t1
    ON t.code = t1.code
   AND t.consolidation_id = t1.consolidation_id
JOIN dbo.t_ref_region v
    ON t1.region = v.region
   AND t.consolidation_id = v.consolidation_id;

-- =======================================================================================
-- 13. VIEW nsa_v_feed_source_code
-- =======================================================================================
CREATE VIEW dbo.nsa_v_feed_source_code AS
SELECT DISTINCT
    f.feed_code,
    sc.source_code,
    sc.mnemonic AS sc_mnemonic,
    sc.name AS sc_name,
    sc.content_collection_id AS sc_content_collection_id,
    sc.consolidation_id
FROM dbo.t_mapped_source_code sc
JOIN dbo.ucdp_v_feed_to_sc usa
    ON sc.mnemonic = usa.source_code
JOIN dbo.t_feeds f
    ON usa.feed_code = f.feed_code
   AND sc.consolidation_id = f.consolidation_id;

-- =======================================================================================
-- 14. VIEW nsa_v_feed_to_codes
-- =======================================================================================
CREATE VIEW dbo.nsa_v_feed_to_codes AS
-- Source codes (NS)
SELECT
    v.source_code AS code,
    'NS' AS code_type,
    v.feed_code,
    v.consolidation_id
FROM dbo.t_feed_source_code v
UNION
-- Product codes (NP)
SELECT DISTINCT
    pc.product_code AS code,
    'NP' AS code_type,
    tp.feed_code,
    tp.consolidation_id
FROM dbo.t_feed_source_code tp
JOIN dbo.t_product_code_source_code pc
    ON pc.source_code = tp.source_code
   AND pc.consolidation_id = tp.consolidation_id;

-- =======================================================================================
-- 15. VIEW nsa_v_not_covered_feeds
-- =======================================================================================
-- group_concat function in MySql is replaced by STRING_AGG in MSSQL and to avoid grouping by feed_code 
-- it is used distinct subqueries.
-- ========================================================================================
CREATE VIEW dbo.nsa_v_not_covered_feeds AS
SELECT
    t.feed_code AS [Feed UCDP],
    t.feed_code AS [Feed To Source Code],
    d.source_codes AS [UCDP Source Code],
    CONVERT(VARCHAR(30), d.source_code_count) AS [Count Source Codes mapped],
    'Source Code Check' AS [Check Type],
    'No UCDP Source Code in RCS/RDS/NewsRoom' AS [Reason]
FROM (
    SELECT DISTINCT feed_code
    FROM dbo.ucdp_feed_to_sc
) t
OUTER APPLY (
    SELECT
        STRING_AGG(sub.source_code, ', ')
            WITHIN GROUP (ORDER BY sub.source_code) AS source_codes,
        CAST(COUNT(*) AS VARCHAR(30)) AS source_code_count
    FROM (
        SELECT DISTINCT t2.source_code
        FROM dbo.ucdp_feed_to_sc t2
        LEFT JOIN dbo.t_all_source_code sc2
            ON t2.source_code = sc2.mnemonic
        WHERE t2.feed_code = t.feed_code
          AND sc2.source_code IS NULL
    ) sub
) d
WHERE d.source_code_count > 0
UNION ALL
-- Feed Check
SELECT
    f.feed_code AS [Feed UCDP],
    t.feed_code AS [Feed To Source Code],
    '' AS [UCDP Source Code],
    '' AS [Count Source Codes mapped],
    'Feed Check' AS [Check Type],
    'Feed exists but not mapped to any Source Code' AS [Reason]
FROM dbo.t_feeds f
LEFT JOIN dbo.ucdp_feed_to_sc t
    ON f.feed_code = t.feed_code
WHERE t.feed_code IS NULL;

-- =======================================================================================
-- 16. VIEW ucdp_v_feed_to_sc
-- =======================================================================================
CREATE VIEW dbo.ucdp_v_feed_to_sc AS
SELECT
    u.feed_code,
    u.source_code,
    u.snapshot_id
FROM dbo.ucdp_feed_to_sc u
WHERE u.snapshot_id IN (
    SELECT p.snapshot_id
    FROM dbo.t_dm_in_data_snapshot p
    WHERE p.supplier_id = 'S:UCDP'
      AND p.data_type = 'ALL'
      AND p.latest = 'Y'
);

-- =======================================================================================
-- 17. VIEW nsa_v_mapped_source_code
-- =======================================================================================
CREATE VIEW dbo.nsa_v_mapped_source_code AS
SELECT DISTINCT
    f.source_code,
    f.mnemonic,
    f.name,
    f.descr,
    f.status,
    f.availability,
    f.content_collection_id,
    f.supplier_id,
    f.consolidation_id
FROM dbo.t_all_source_code f
JOIN (
    SELECT DISTINCT
        usa.source_code
    FROM dbo.ucdp_v_feed_to_sc usa
) u
    ON f.mnemonic = u.source_code;

-- =======================================================================================
-- 18. VIEW rds_v_all_pc_pe
-- =======================================================================================
-- trailing function in MySQL is replaced by combination of LEFT and LEN functions in MSSQL,
-- and TRY_CAST is used to avoid errors during conversion if the value cannot be converted to number
-- ========================================================================================
CREATE VIEW dbo.rds_v_all_pc_pe AS
SELECT
    r.product_code,
    CAST(
        LEFT(rd2.value, LEN(rd2.value) - 
            CASE 
                WHEN RIGHT(rd2.value, 1) = 'M' THEN 1 
                ELSE 0 
            END
        ) AS BIGINT
    ) AS pe_code
FROM dbo.rds_v_product_code r
JOIN dbo.rds_v_reference_data rd2
    ON rd2.code = r.product_code
   AND rd2.code_type = 'NP'
   AND rd2.data_type = 'RUN_PE'
WHERE rd2.value IS NOT NULL
  AND rd2.value NOT IN ('N/A', 'NA');

-- =======================================================================================
-- 19. VIEW rds_v_pc_pe
-- =======================================================================================
-- trailing function in MySQL is replaced by combination of LEFT and LEN functions in MSSQL,
-- and TRY_CAST is used to avoid errors during conversion if the value cannot be converted to number
-- ========================================================================================
CREATE VIEW dbo.rds_v_pc_pe AS
SELECT
    r.product_code,
    TRY_CAST(
        LEFT(
            rd2.value,
            LEN(rd2.value) - 
            CASE 
                WHEN RIGHT(rd2.value, 1) = 'M' THEN 1
                ELSE 0
            END
        ) AS BIGINT
    ) AS pe_code
FROM dbo.rds_product_code r
JOIN dbo.rds_reference_data rd
    ON r.product_code = rd.code
   AND rd.code_type = 'NP'
   AND rd.data_type = 'IS_NOT_PROD_CODE'
   AND rd.value = 'N'
LEFT JOIN dbo.rds_reference_data rd2
    ON rd2.code = rd.code
   AND rd2.code_type = 'NP'
   AND rd2.data_type = 'RUN_PE';

-- =======================================================================================
-- 20. VIEW tmp_nsa_v_feed_all_grouped
-- =======================================================================================
-- OUTER APPLY joins and STRING_AGG function are used to replace group_concat and 
-- avoid grouping by all non aggregated columns
-- =======================================================================================
CREATE VIEW dbo.tmp_nsa_v_feed_all_grouped AS
SELECT
    f.feed_code,
    f.description,
    f.parser,
    f.parser_descr,
    f.onboarder,
    f.onboarder_descr,
    f.copyrightOwner,
    sc.sc,
    sc.sc_count,
    pc.pc,
    pc.pc_count,
    pe.pe_code,
    pe.pe_count,
    cc.content_collection,
    cc.cc_count,
    f.feed_instance_count,
    f.consolidation_id
FROM dbo.t_feeds f
-- Source codes
OUTER APPLY (
    SELECT
        STRING_AGG(sub.source_code, ', ')
            WITHIN GROUP (ORDER BY sub.source_code) AS sc,
        COUNT(*) AS sc_count
    FROM (
        SELECT DISTINCT sc.source_code
        FROM dbo.t_feed_source_code sc
        WHERE sc.feed_code = f.feed_code
          AND sc.consolidation_id = f.consolidation_id
    ) sub
) sc
-- Product codes
OUTER APPLY (
    SELECT
        STRING_AGG(sub.product_code, ', ')
            WITHIN GROUP (ORDER BY sub.product_code) AS pc,
        COUNT(*) AS pc_count
    FROM (
        SELECT DISTINCT pc.product_code
        FROM dbo.t_feed_product_code pc
        WHERE pc.feed_code = f.feed_code
          AND pc.consolidation_id = f.consolidation_id
    ) sub
) pc
-- PE codes
OUTER APPLY (
    SELECT
        STRING_AGG(sub.pe_code, ', ')
            WITHIN GROUP (ORDER BY sub.pe_code) AS pe_code,
        COUNT(*) AS pe_count
    FROM (
        SELECT DISTINCT pe.pe_code
        FROM dbo.t_feed_pe_code pe
        WHERE pe.feed_code = f.feed_code
          AND pe.consolidation_id = f.consolidation_id
    ) sub
) pe
-- Content collections
OUTER APPLY (
    SELECT
        STRING_AGG(sub.content_collection, ', ')
            WITHIN GROUP (ORDER BY sub.content_collection) AS content_collection,
        COUNT(*) AS cc_count
    FROM (
        SELECT DISTINCT cc.content_collection, cc.content_collection_id
        FROM dbo.t_feed_source_code sc
        JOIN dbo.t_content_collection cc
            ON sc.sc_content_collection_id = cc.content_collection_id
        WHERE sc.feed_code = f.feed_code
          AND sc.consolidation_id = f.consolidation_id
    ) sub
) cc;

-- =======================================================================================
-- 21. bpsa_v_source_code_pe_code
-- =======================================================================================
-- trailing function in MySQL is replaced by combination of LEFT and LEN functions in MSSQL,
-- and TRY_CAST is used to avoid errors during conversion if the value cannot be converted to number
-- =======================================================================================
CREATE VIEW dbo.bpsa_v_source_code_pe_code AS
SELECT
    r.source_code,
    TRY_CAST(
        CASE
            WHEN PATINDEX('%[^0-9]%', r.value) > 0
            THEN LEFT(r.value, PATINDEX('%[^0-9]%', r.value) - 1)
            ELSE r.value
        END
        AS BIGINT
    ) AS pe_code
FROM dbo.bpsa_reference_data r
WHERE r.category = 'ENTITLEMENT'
  AND r.data_type = 'PECODE';

-- =======================================================================================
-- 22. VIEW nsa_v_all_source_codes
-- =======================================================================================
-- Use CTE (WITH construction) to symplify the query and avoid repetition of code for handling mnemonic 
-- and filtering by snapshot_id.
-- =======================================================================================
CREATE VIEW dbo.nsa_v_all_source_codes AS
WITH
rcs AS (
    SELECT
        r.source_code,
        r.name,
        r.definition,
        CASE 
            WHEN r.source_code LIKE 'NS:%'
            THEN SUBSTRING(r.source_code, 4, LEN(r.source_code))
            ELSE r.source_code
        END AS mnemonic
    FROM dbo.rcs_v_source_code r
),
bpsa AS (
    SELECT
        r.source_code,
        r.name,
        r.descr,
        r.status,
        r.availability,
        r.contentSet,
        r.publisher,
        r.url,
        r.snapshot_id,
        CASE 
            WHEN r.source_code LIKE 'NS:%'
            THEN SUBSTRING(r.source_code, 4, LEN(r.source_code))
            ELSE r.source_code
        END AS mnemonic
    FROM dbo.bpsa_source_code r
),
rds AS (
    SELECT
        r.source_code,
        r.source_name,
        CASE 
            WHEN r.source_code LIKE 'NS:%'
            THEN SUBSTRING(r.source_code, 4, LEN(r.source_code))
            ELSE r.source_code
        END AS mnemonic
    FROM dbo.rds_v_source_code r
),
bpsa_pc AS (
    SELECT
        t.source_code,
        t.product_code,
        CASE 
            WHEN t.source_code LIKE 'NS:%'
            THEN SUBSTRING(t.source_code, 4, LEN(t.source_code))
            ELSE t.source_code
        END AS mnemonic
    FROM dbo.bpsa_v_product_code_source_code t
),
rds_ref AS (
    SELECT
        m.code,
        m.value,
        m.code_type,
        m.data_type,
        m.snapshot_id,
        CASE 
            WHEN m.code LIKE 'NS:%'
            THEN SUBSTRING(m.code, 4, LEN(m.code))
            ELSE m.code
        END AS mnemonic
    FROM dbo.rds_reference_data m
),
rds_ref_max AS (
    SELECT MAX(snapshot_id) AS snapshot_id
    FROM dbo.rds_reference_data
    WHERE code_type = 'NS'
)
SELECT
    r.source_code,
    r.mnemonic,
    r.name,
    r.definition AS descr,
    'ACTIVE' AS status,
    'No Data' AS availability,
    CASE
        WHEN t.product_code IS NOT NULL AND m.value = 'false' THEN 'HV'
        WHEN t.product_code IS NULL AND m.value = 'false' THEN 'NW'
    END AS content_collection_id,
    'S:RCS' AS supplier_id,
    CAST(NULL AS VARCHAR) AS publisher,
    CAST(NULL AS VARCHAR) AS url
FROM rcs r
LEFT JOIN bpsa_pc t
    ON r.mnemonic = t.mnemonic
   AND t.product_code = 'RFTHVS'
LEFT JOIN rds_ref m
    ON r.mnemonic = m.mnemonic
   AND m.code_type = 'NS'
   AND m.data_type = 'EXCLUDE_FROM_EIKON'
   AND m.snapshot_id = (SELECT snapshot_id FROM rds_ref_max)
UNION
SELECT
    r.source_code,
    r.mnemonic,
    r.name,
    r.descr,
    r.status,
    r.availability,
    CASE
        WHEN r.contentSet = 'WEBNEWS' THEN 'WN'
        WHEN r.contentSet = 'NEWSROOM' AND t.product_code IS NOT NULL THEN 'HV'
        WHEN r.contentSet = 'NEWSROOM' AND t.product_code IS NULL THEN 'NR'
        WHEN r.contentSet = 'REFINITIV' THEN 'NR'
        ELSE r.contentSet
    END,
    'S:NR',
    r.publisher,
    r.url
FROM bpsa r
LEFT JOIN bpsa_pc t
    ON r.source_code = t.source_code
   AND t.product_code = 'RFTHVS'
WHERE r.snapshot_id IN (
        SELECT p.snapshot_id
        FROM dbo.t_dm_in_data_snapshot p
        WHERE p.supplier_id = 'S:NR'
          AND p.data_type = 'ALL'
          AND p.latest = 'Y'
    )
  AND NOT EXISTS (
        SELECT 1
        FROM rcs r2
        WHERE r2.mnemonic = r.mnemonic
    )
UNION
SELECT
    r.source_code,
    r.mnemonic,
    r.source_name,
    r.source_name,
    'ACTIVE',
    'No Data',
    CASE
        WHEN t.product_code IS NOT NULL AND m.value = 'false' THEN 'HV'
        WHEN t.product_code IS NULL AND m.value = 'false' THEN 'NW'
    END,
    'S:RDS',
    NULL,
    NULL
FROM rds r
LEFT JOIN bpsa_pc t
    ON r.mnemonic = t.mnemonic
   AND t.product_code = 'RFTHVS'
LEFT JOIN rds_ref m
    ON r.mnemonic = m.mnemonic
   AND m.code_type = 'NS'
   AND m.data_type = 'EXCLUDE_FROM_EIKON'
   AND m.snapshot_id = (SELECT snapshot_id FROM rds_ref_max)
WHERE NOT EXISTS (
        SELECT 1
        FROM bpsa b
        WHERE b.mnemonic = r.mnemonic
    )
  AND NOT EXISTS (
        SELECT 1
        FROM rcs r2
        WHERE r2.mnemonic = r.mnemonic
    );

-- =======================================================================================
-- 23. nsa_v_mrn_pe_search
-- =======================================================================================
CREATE VIEW dbo.nsa_v_mrn_pe_search AS
SELECT
    p.pe_code,
    m3.value AS product_code,
    m.value AS source_code,
    m1.value AS lang_code,
    m5.value AS instance_code,
    m4.value AS subject_code,
    m2.value AS urgency,
    m6.value AS fullLanguage,
    ps.pe_name
FROM dbo.t_mrn_pe_rules p
JOIN dbo.t_ps2_pe ps
    ON p.pe_code = ps.pe_code
JOIN dbo.t_dm_in_data_snapshot pes
    ON pes.snapshot_id = ps.snapshot_id
   AND pes.latest = 'Y'
LEFT JOIN dbo.t_mrn_rule_details m
    ON p.pe_code = m.pe_code
   AND m.type = 'PROVIDER'
   AND p.snapshot_id = m.snapshot_id
LEFT JOIN dbo.t_mrn_rule_details m1
    ON p.pe_code = m1.pe_code
   AND m1.type = 'LANGUAGE'
   AND p.snapshot_id = m1.snapshot_id
LEFT JOIN dbo.t_mrn_rule_details m2
    ON p.pe_code = m2.pe_code
   AND m2.type = 'URGENCY'
   AND p.snapshot_id = m2.snapshot_id
LEFT JOIN dbo.t_mrn_rule_details m3
    ON p.pe_code = m3.pe_code
   AND m3.type = 'AUDIENCE'
   AND p.snapshot_id = m3.snapshot_id
LEFT JOIN dbo.t_mrn_rule_details m4
    ON p.pe_code = m4.pe_code
   AND m4.type = 'SUBJECT'
   AND p.snapshot_id = m4.snapshot_id
LEFT JOIN dbo.t_mrn_rule_details m5
    ON p.pe_code = m5.pe_code
   AND m5.type = 'INSTANCE'
   AND p.snapshot_id = m5.snapshot_id
LEFT JOIN dbo.t_mrn_rule_details m6
    ON p.pe_code = m6.pe_code
   AND m6.type = 'FULL_LANGUAGE'
   AND p.snapshot_id = m6.snapshot_id
WHERE p.snapshot_id IN (
    SELECT s.snapshot_id
    FROM dbo.t_dm_in_data_snapshot s
    WHERE s.supplier_id = 'S:UCDP'
      AND s.data_type = 'MRN'
      AND s.latest = 'Y'
);

-- =======================================================================================
-- 24. VIEW nsa_v_all_pc_to_pe
-- =======================================================================================
CREATE VIEW dbo.nsa_v_all_pc_to_pe AS
SELECT
    t.product_code,
    p.pe_code,
    t.consolidation_id
FROM dbo.t_all_product_code t
JOIN (
    SELECT
        v.product_code,
        v.pe_code
    FROM dbo.rds_v_all_pc_pe v
    UNION
    SELECT
        m.product_code,
        m.pe_code
    FROM dbo.nsa_v_mrn_pe_pc m
) p
    ON p.product_code = t.product_code;

-- =======================================================================================
-- 25. VIEW nsa_v_all_product_code_source_code
-- =======================================================================================
-- Use CTE to handle the normalization of source_code and product_code in one place and 
-- simplify the main query.
-- =======================================================================================
CREATE VIEW dbo.nsa_v_all_product_code_source_code AS
WITH rpc_norm AS (
    SELECT
        rpc.*,
        CASE
            WHEN rpc.source_code LIKE 'NS:%'
            THEN SUBSTRING(rpc.source_code, 4, LEN(rpc.source_code))
            ELSE rpc.source_code
        END AS source_code_norm,
        CASE
            WHEN rpc.product_code LIKE 'NP:%'
            THEN SUBSTRING(rpc.product_code, 4, LEN(rpc.product_code))
            ELSE rpc.product_code
        END AS product_code_norm
    FROM dbo.rcs_v_product_code_source_code rpc
)
SELECT DISTINCT
    pc.product_code,
    sc.source_code,
    pc.mnemonic AS pc_mnemonic,
    sc.mnemonic AS sc_mnemonic,
    sc.consolidation_id
FROM dbo.t_all_source_code sc
JOIN dbo.bpsa_v_product_code_source_code bpc
    ON sc.mnemonic = bpc.source_code
JOIN dbo.t_all_product_code pc
    ON bpc.product_code = pc.mnemonic
   AND sc.consolidation_id = pc.consolidation_id
UNION
SELECT DISTINCT
    pc.product_code,
    sc.source_code,
    pc.mnemonic AS pc_mnemonic,
    sc.mnemonic AS sc_mnemonic,
    sc.consolidation_id
FROM dbo.t_all_source_code sc
JOIN rpc_norm rpc
    ON sc.mnemonic = rpc.source_code_norm
JOIN dbo.t_all_product_code pc
    ON rpc.product_code_norm = pc.mnemonic
   AND sc.consolidation_id = pc.consolidation_id;

-- =======================================================================================
-- 26. VIEW nsa_v_all_product_codes
-- =======================================================================================
-- Use CTE to handle the normalization of product_code in one place and simplify the main query.
-- Also all leading functions are replaced by combination of SUBSTRING and LEN functions in MSSQL.
-- =======================================================================================
CREATE VIEW dbo.nsa_v_all_product_codes AS
WITH rcs_norm AS (
    SELECT
        r.product_code,
        r.name,
        r.definition,
        CASE
            WHEN r.product_code LIKE 'NP:%'
            THEN SUBSTRING(r.product_code, 4, LEN(r.product_code))
            ELSE r.product_code
        END AS mnemonic
    FROM dbo.rcs_v_product_code r
),
rds_norm AS (
    SELECT
        r.product_code,
        r.product_name,
        CASE
            WHEN r.product_code LIKE 'NP:%'
            THEN SUBSTRING(r.product_code, 4, LEN(r.product_code))
            ELSE r.product_code
        END AS mnemonic
    FROM dbo.rds_v_product_code r
)
SELECT
    r.product_code,
    r.mnemonic,
    r.name,
    r.definition AS descr,
    NULL AS content_collection_id,
    'S:RCS' AS supplier_id
FROM rcs_norm r
UNION
SELECT
    r.product_code,
    r.mnemonic,
    r.product_name AS name,
    r.product_name AS descr,
    NULL AS content_collection_id,
    'S:RDS' AS supplier_id
FROM rds_norm r
WHERE r.mnemonic NOT IN (
    SELECT DISTINCT mnemonic
    FROM rcs_norm
)
AND r.product_code <> 'No Product Code';

-- =======================================================================================
-- 27. VIEW view_product_source_codes
-- =======================================================================================
CREATE VIEW dbo.view_product_source_codes AS
SELECT DISTINCT
    pc.product_code,
    CAST(NULL AS VARCHAR) AS source_code,
    pc.name,
    pc.content_collection AS contentCollection,
    pc.country,
    vc.country_id,
    vr.region_id,
    vi.industry_id
FROM dbo.t_all_pc_ref_grouped pc
JOIN dbo.t_dm_consolidation c
    ON c.consolidation_id = pc.consolidation_id
LEFT JOIN dbo.nsa_v_pc_country vc
    ON vc.product_code = pc.product_code
   AND c.consolidation_id = vc.consolidation_id
LEFT JOIN dbo.nsa_v_pc_region vr
    ON vr.product_code = pc.product_code
   AND c.consolidation_id = vr.consolidation_id
LEFT JOIN dbo.nsa_v_pc_industry vi
    ON vi.product_code = pc.product_code
   AND c.consolidation_id = vi.consolidation_id
WHERE c.latest = 'Y'
  AND c.status = 'COMPLETED'
UNION
SELECT DISTINCT
    CAST(NULL AS VARCHAR) AS product_code,
    sc.source_code,
    sc.name,
    sc.content_collection AS contentCollection,
    sc.country,
    vc.country_id,
    vr.region_id,
    vi.industry_id
FROM dbo.t_all_sc_ref_grouped sc
JOIN dbo.t_dm_consolidation c
    ON c.consolidation_id = sc.consolidation_id
JOIN dbo.nsa_v_sc_country vc
    ON vc.source_code = sc.source_code
   AND c.consolidation_id = vc.consolidation_id
JOIN dbo.nsa_v_sc_region vr
    ON vr.source_code = sc.source_code
   AND c.consolidation_id = vr.consolidation_id
JOIN dbo.nsa_v_sc_industry vi
    ON vi.source_code = sc.source_code
   AND c.consolidation_id = vi.consolidation_id
WHERE c.latest = 'Y'
  AND c.status = 'COMPLETED';



-- =======================================================================================
-- Execute on MSSQL
-- =======================================================================================

-- Get row counts for all views to verify that they are working and returning data as expected.
SELECT 'nsa_v_all_pc_ref_grouped' AS view_name, COUNT(*) AS row_count 
FROM _nsa_v_all_pc_ref_grouped
UNION ALL
SELECT 'nsa_v_all_sc_pc_ref_grouped', COUNT(*) FROM _nsa_v_all_sc_pc_ref_grouped
UNION ALL
SELECT 'nsa_v_all_sc_ref_grouped', COUNT(*) FROM _nsa_v_all_sc_ref_grouped
UNION ALL
SELECT 'nsa_v_all_sc_ref_grouped_1', COUNT(*) FROM _nsa_v_all_sc_ref_grouped_1
UNION ALL
SELECT 'nsa_v_all_sc_ref_grouped_2', COUNT(*) FROM _nsa_v_all_sc_ref_grouped_2
UNION ALL
SELECT 'nsa_v_feed_content_collection', COUNT(*) FROM _nsa_v_feed_content_collection
UNION ALL
SELECT 'nsa_v_feed_country', COUNT(*) FROM _nsa_v_feed_country
UNION ALL
SELECT 'nsa_v_feed_industry', COUNT(*) FROM _nsa_v_feed_industry
UNION ALL
SELECT 'nsa_v_feed_region', COUNT(*) FROM _nsa_v_feed_region
UNION ALL
SELECT 'nsa_v_feed_source_code', COUNT(*) FROM _nsa_v_feed_source_code
UNION ALL
SELECT 'nsa_v_feed_to_codes', COUNT(*) FROM _nsa_v_feed_to_codes
UNION ALL
SELECT 'nsa_v_feeds', COUNT(*) FROM _nsa_v_feeds
UNION ALL
SELECT 'nsa_v_mapped_source_code', COUNT(*) FROM _nsa_v_mapped_source_code
UNION ALL
SELECT 'nsa_v_news_map', COUNT(*) FROM _nsa_v_news_map
UNION ALL
SELECT 'nsa_v_news_map_variant', COUNT(*) FROM _nsa_v_news_map_variant
UNION ALL
SELECT 'nsa_v_not_covered_feeds', COUNT(*) FROM _nsa_v_not_covered_feeds
UNION ALL
SELECT 'rds_v_all_pc_pe', COUNT(*) FROM _rds_v_all_pc_pe
UNION ALL
SELECT 'rds_v_pc_pe', COUNT(*) FROM _rds_v_pc_pe
UNION ALL
SELECT 'tmp_nsa_v_feed_all_grouped', COUNT(*) FROM _tmp_nsa_v_feed_all_grouped
UNION ALL
SELECT 'ucdp_v_feed_to_sc', COUNT(*) FROM _ucdp_v_feed_to_sc
UNION ALL
SELECT 'bpsa_v_source_code_pe_code', COUNT(*) FROM _bpsa_v_source_code_pe_code
UNION ALL
SELECT 'nsa_v_all_source_codes', COUNT(*) FROM _nsa_v_all_source_codes
UNION ALL
SELECT 'nsa_v_mrn_pe_search', COUNT(*) FROM _nsa_v_mrn_pe_search
UNION ALL
SELECT 'nsa_v_all_pc_to_pe', COUNT(*) FROM _nsa_v_all_pc_to_pe
UNION ALL
SELECT 'nsa_v_all_product_code_source_code', COUNT(*) FROM _nsa_v_all_product_code_source_code
UNION ALL
SELECT 'nsa_v_all_product_codes', COUNT(*) FROM _nsa_v_all_product_codes
UNION ALL
SELECT 'view_product_source_codes', COUNT(*) FROM _view_product_source_codes
ORDER BY 1
;

-- Get column lists for all views to verify that they are working and returning expected columns.
SELECT
    v.name AS view_name,
    STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY c.column_id) AS columns_list
FROM sys.views v
JOIN sys.columns c
    ON v.object_id = c.object_id
WHERE v.name IN (
'nsa_v_all_pc_ref_grouped',
'nsa_v_all_sc_pc_ref_grouped',
'nsa_v_all_sc_ref_grouped',
'nsa_v_all_sc_ref_grouped_1',
'nsa_v_all_sc_ref_grouped_2',
'nsa_v_feed_content_collection',
'nsa_v_feed_country',
'nsa_v_feed_industry',
'nsa_v_feed_region',
'nsa_v_feed_source_code',
'nsa_v_feed_to_codes',
'nsa_v_feeds',
'nsa_v_mapped_source_code',
'nsa_v_news_map',
'nsa_v_news_map_variant',
'nsa_v_not_covered_feeds',
'rds_v_all_pc_pe',
'rds_v_pc_pe',
'tmp_nsa_v_feed_all_grouped',
'ucdp_v_feed_to_sc',
'bpsa_v_source_code_pe_code',
'nsa_v_all_source_codes',
'nsa_v_mrn_pe_search',
'nsa_v_all_pc_to_pe',
'nsa_v_all_product_code_source_code',
'nsa_v_all_product_codes',
'view_product_source_codes'
)
GROUP BY v.name
ORDER BY v.name;


-- =======================================================================================
-- Execute on MySQL
-- =======================================================================================

-- Get row counts for all views to verify that they are working and returning data as expected.
SELECT 'nsa_v_all_pc_ref_grouped' AS view_name, COUNT(*) AS row_count 
FROM nsa_v_all_pc_ref_grouped
UNION ALL
SELECT 'nsa_v_all_sc_pc_ref_grouped', COUNT(*) FROM nsa_v_all_sc_pc_ref_grouped
UNION ALL
SELECT 'nsa_v_all_sc_ref_grouped', COUNT(*) FROM nsa_v_all_sc_ref_grouped
UNION ALL
SELECT 'nsa_v_all_sc_ref_grouped_1', COUNT(*) FROM nsa_v_all_sc_ref_grouped_1
UNION ALL
SELECT 'nsa_v_all_sc_ref_grouped_2', COUNT(*) FROM nsa_v_all_sc_ref_grouped_2
UNION ALL
SELECT 'nsa_v_feed_content_collection', COUNT(*) FROM nsa_v_feed_content_collection
UNION ALL
SELECT 'nsa_v_feed_country', COUNT(*) FROM nsa_v_feed_country
UNION ALL
SELECT 'nsa_v_feed_industry', COUNT(*) FROM nsa_v_feed_industry
UNION ALL
SELECT 'nsa_v_feed_region', COUNT(*) FROM nsa_v_feed_region
UNION ALL
SELECT 'nsa_v_feed_source_code', COUNT(*) FROM nsa_v_feed_source_code
UNION ALL
SELECT 'nsa_v_feed_to_codes', COUNT(*) FROM nsa_v_feed_to_codes
UNION ALL
SELECT 'nsa_v_feeds', COUNT(*) FROM nsa_v_feeds
UNION ALL
SELECT 'nsa_v_mapped_source_code', COUNT(*) FROM nsa_v_mapped_source_code
UNION ALL
SELECT 'nsa_v_news_map', COUNT(*) FROM nsa_v_news_map
UNION ALL
SELECT 'nsa_v_news_map_variant', COUNT(*) FROM nsa_v_news_map_variant
UNION ALL
SELECT 'nsa_v_not_covered_feeds', COUNT(*) FROM nsa_v_not_covered_feeds
UNION ALL
SELECT 'rds_v_all_pc_pe', COUNT(*) FROM rds_v_all_pc_pe
UNION ALL
SELECT 'rds_v_pc_pe', COUNT(*) FROM rds_v_pc_pe
UNION ALL
SELECT 'tmp_nsa_v_feed_all_grouped', COUNT(*) FROM tmp_nsa_v_feed_all_grouped
UNION ALL
SELECT 'ucdp_v_feed_to_sc', COUNT(*) FROM ucdp_v_feed_to_sc
UNION ALL
SELECT 'bpsa_v_source_code_pe_code', COUNT(*) FROM bpsa_v_source_code_pe_code
UNION ALL
SELECT 'nsa_v_all_source_codes', COUNT(*) FROM nsa_v_all_source_codes
UNION ALL
SELECT 'nsa_v_mrn_pe_search', COUNT(*) FROM nsa_v_mrn_pe_search
UNION ALL
SELECT 'nsa_v_all_pc_to_pe', COUNT(*) FROM nsa_v_all_pc_to_pe
UNION ALL
SELECT 'nsa_v_all_product_code_source_code', COUNT(*) FROM nsa_v_all_product_code_source_code
UNION ALL
SELECT 'nsa_v_all_product_codes', COUNT(*) FROM nsa_v_all_product_codes
UNION ALL
SELECT 'view_product_source_codes', COUNT(*) FROM view_product_source_codes
ORDER BY 1
;

-- Get column lists for all views to verify that they are working and returning expected columns.
SELECT
    TABLE_NAME AS view_name,
    GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION SEPARATOR ', ') AS columns_list
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
'nsa_v_all_pc_ref_grouped',
'nsa_v_all_sc_pc_ref_grouped',
'nsa_v_all_sc_ref_grouped',
'nsa_v_all_sc_ref_grouped_1',
'nsa_v_all_sc_ref_grouped_2',
'nsa_v_feed_content_collection',
'nsa_v_feed_country',
'nsa_v_feed_industry',
'nsa_v_feed_region',
'nsa_v_feed_source_code',
'nsa_v_feed_to_codes',
'nsa_v_feeds',
'nsa_v_mapped_source_code',
'nsa_v_news_map',
'nsa_v_news_map_variant',
'nsa_v_not_covered_feeds',
'rds_v_all_pc_pe',
'rds_v_pc_pe',
'tmp_nsa_v_feed_all_grouped',
'ucdp_v_feed_to_sc',
'bpsa_v_source_code_pe_code',
'nsa_v_all_source_codes',
'nsa_v_mrn_pe_search',
'nsa_v_all_pc_to_pe',
'nsa_v_all_product_code_source_code',
'nsa_v_all_product_codes',
'view_product_source_codes'
)
GROUP BY TABLE_NAME
ORDER BY TABLE_NAME;