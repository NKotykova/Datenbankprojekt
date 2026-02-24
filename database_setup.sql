-- ============================================================
-- Schritt 2: Tabellen erstellen und Daten importieren
-- ============================================================
-- Hinweis: Die IDs kommen aus den CSV-Dateien (via Python/pandas).
-- Deshalb wird SERIAL nicht verwendet -- die Sequenz würde sonst
-- mit den vorhandenen IDs in Konflikt geraten.
-- Stattdessen: INTEGER PRIMARY KEY, IDs werden aus CSV übernommen.

BEGIN;

CREATE TABLE prodkategorie (
    "ProdkategorieID" INTEGER PRIMARY KEY,
    "Kategorie"       TEXT NOT NULL
);

CREATE TABLE produkte (
    "ProduktID"       INTEGER PRIMARY KEY,
    "ProduktName"     TEXT NOT NULL,
    -- NUMERIC(10,2) statt INTEGER, damit Cent-Beträge korrekt gespeichert werden
    "ProduktPreis"    NUMERIC(10,2),
    "ProdkategorieID" INTEGER REFERENCES prodkategorie("ProdkategorieID")
);

CREATE TABLE kunden (
    "KundenID"        INTEGER PRIMARY KEY,
    "KundeVorname"    TEXT,
    "KundeNachname"   TEXT,
    "KundeStrasse"    TEXT,
    "KundePostzahl"   TEXT,
    "KundeOrt"        TEXT,
    "KundeKreditkarte" TEXT
);

CREATE TABLE verkaeufe (
    "BestellID"    INTEGER PRIMARY KEY,
    "Menge"        INTEGER,
    "Bestelldatum" DATE,
    "KundenID"     INTEGER REFERENCES kunden("KundenID"),
    "ProduktID"    INTEGER REFERENCES produkte("ProduktID")
);

COMMIT;

-- Daten prüfen: Import über Python (sales_analysis.ipynb) erfolgreich?
SELECT * FROM prodkategorie LIMIT 5;
SELECT * FROM produkte      LIMIT 5;
SELECT * FROM kunden        LIMIT 5;
SELECT * FROM verkaeufe     LIMIT 5;


-- ============================================================
-- Schritt 3: Rollen und Benutzer anlegen
-- ============================================================
-- Zwei Rollen: callcenter_mitarbeiter und datenanalyst
-- Jede Rolle bekommt nur die Rechte, die sie wirklich braucht.

BEGIN;

CREATE ROLE callcenter_mitarbeiter;
CREATE ROLE datenanalyst;

-- Callcenter darf nur die Kundentabelle lesen
-- (wird in Schritt 4 durch einen View ersetzt)
GRANT SELECT ON kunden TO callcenter_mitarbeiter;

-- Datenanalyst darf alle Tabellen lesen, aber nichts schreiben
GRANT SELECT ON kunden, produkte, prodkategorie, verkaeufe TO datenanalyst;

-- Benutzer anlegen
-- Achtung: Passwörter hier nur als Platzhalter -- in der Produktion
-- immer Umgebungsvariablen oder einen Secrets-Manager verwenden!
CREATE USER mitarbeiter PASSWORD '********';
CREATE USER schmidt     PASSWORD '********';

-- Rollen den Benutzern zuweisen
GRANT callcenter_mitarbeiter TO mitarbeiter;
GRANT datenanalyst           TO schmidt;

COMMIT;

-- Zugriffstest: mitarbeiter darf kunden lesen, aber nicht produkte
SET ROLE mitarbeiter;
SELECT * FROM kunden;    -- erwartet: Ergebnis
SELECT * FROM produkte;  -- erwartet: Fehler (keine Rechte)
SET ROLE NONE;

-- Zugriffstest: datenanalyst darf alle Tabellen lesen
SET ROLE datenanalyst;
SELECT * FROM produkte;
SELECT * FROM kunden;
SET ROLE NONE;

-- Aktuellen Benutzer anzeigen (zur Kontrolle)
SELECT current_user;


-- ============================================================
-- Schritt 4: Sicherheits-View für Kreditkartendaten
-- ============================================================
-- Problem: callcenter_mitarbeiter sieht vollständige Kreditkartennummern.
-- Lösung: View erstellen, der nur die letzten 4 Ziffern zeigt.
-- Danach: direkten Zugriff auf die Tabelle entziehen.

-- View mit maskierten Kreditkartendaten
CREATE VIEW kunden_view_sicher AS
SELECT
    "KundenID",
    "KundeVorname",
    "KundeNachname",
    '************* ' || RIGHT("KundeKreditkarte", 3) AS Kreditkarte_letzte3
FROM kunden;

BEGIN;

-- Direkten Zugriff auf kunden für alle und callcenter_mitarbeiter entziehen
REVOKE ALL ON kunden FROM PUBLIC;
REVOKE ALL ON kunden FROM callcenter_mitarbeiter;

-- Stattdessen: nur Lesezugriff auf den sicheren View erlauben
GRANT SELECT ON kunden_view_sicher TO callcenter_mitarbeiter;

COMMIT;

-- Test: mitarbeiter darf View lesen, aber nicht die echte Tabelle
SET ROLE mitarbeiter;
SELECT * FROM kunden_view_sicher; -- erwartet: Ergebnis mit maskierten Daten
SELECT * FROM kunden;             -- erwartet: Fehler (kein Zugriff)
SET ROLE NONE;


-- ============================================================
-- Schritt 6: Audit-Trigger für Datenänderungen (optional)
-- ============================================================
-- PostgreSQL unterstützt keine Trigger auf SELECT.
-- Deshalb wird nur protokolliert, wenn Daten geändert werden:
-- INSERT, UPDATE oder DELETE auf der Tabelle kunden.

-- Protokolltabelle: speichert wer, wann, was geändert hat
CREATE TABLE zugriffsprotokoll (
    id           SERIAL PRIMARY KEY,
    benutzername TEXT,
    tabelle      TEXT,
    zugriffsart  TEXT,  -- INSERT, UPDATE oder DELETE
    zugriffszeit TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trigger-Funktion: wird bei jeder Datenänderung aufgerufen
CREATE OR REPLACE FUNCTION log_zugriff()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO zugriffsprotokoll (benutzername, tabelle, zugriffsart)
    VALUES (current_user, TG_TABLE_NAME, TG_OP);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger an die Tabelle kunden hängen
CREATE TRIGGER kunden_zugriff_log
AFTER INSERT OR UPDATE OR DELETE ON kunden
FOR EACH STATEMENT
EXECUTE FUNCTION log_zugriff();

-- Test: als postgres (hat Schreibrechte) eine Änderung vornehmen
-- mitarbeiter hat kein UPDATE-Recht auf kunden -- der Trigger
-- würde gar nicht ausgelöst, da der Befehl vorher scheitert.
-- Deshalb hier als Superuser testen:
UPDATE kunden SET "KundeVorname" = 'Test' WHERE "KundenID" = 1;

-- Protokoll prüfen: Eintrag sollte sichtbar sein
SELECT * FROM zugriffsprotokoll;

-- Änderung rückgängig machen (Originalwert direkt angeben)
UPDATE kunden SET "KundeVorname" = 'Alla' WHERE "KundenID" = 1;


-- ============================================================
-- Schritt 7: Python-Zugriff mit Rollenbeschränkung prüfen
-- ============================================================
-- Die Python-Analyse (sales_analysis.ipynb) läuft als Benutzer schmidt
-- mit der Rolle datenanalyst -- nur Lesen erlaubt, kein Schreiben.

SET ROLE schmidt;

-- Zur Kontrolle: aktuellen Benutzer anzeigen
SELECT current_user, current_setting('role') AS aktive_rolle;

SELECT * FROM kunden;   -- erwartet: Ergebnis
SELECT * FROM produkte; -- erwartet: Ergebnis

-- Schreibversuch -- muss einen Fehler liefern
UPDATE kunden SET "KundeVorname" = 'Test' WHERE "KundenID" = 1;

SET ROLE NONE;


-- ============================================================
-- Schritt 8: Erweiterte Analyse -- Business-Insights
-- ============================================================
-- Sechs Abfragen mit JOIN, GROUP BY, HAVING, CASE WHEN
-- und Window Functions (RANK, SUM OVER).
-- Alle Abfragen laufen als datenanalyst (nur SELECT).
-- ============================================================

SET ROLE schmidt;

-- ------------------------------------------------------------
-- Insight 1: Umsatz pro Produktkategorie
-- ------------------------------------------------------------
-- Uhren und Schmuck dominieren trotz weniger Bestellungen,
-- weil die Einzelpreise extrem hoch sind.

SELECT
    k."Kategorie",
    SUM(v."Menge" * p."ProduktPreis")          AS Gesamtumsatz,
    COUNT(v."BestellID")                        AS Anzahl_Bestellungen,
    ROUND(AVG(v."Menge" * p."ProduktPreis"), 2) AS Durchschnittlicher_Bestellwert
FROM verkaeufe v
JOIN produkte      p ON v."ProduktID"       = p."ProduktID"
JOIN prodkategorie k ON p."ProdkategorieID" = k."ProdkategorieID"
GROUP BY k."Kategorie"
ORDER BY Gesamtumsatz DESC;


-- ------------------------------------------------------------
-- Insight 2: Monatlicher Umsatz -- Saisonalität erkennen
-- ------------------------------------------------------------
-- Oktober 2020 ist der stärkste Monat (120.000 €) --
-- eine einzige Großbestellung (8x Rolex) treibt den Wert.

SELECT
    DATE_TRUNC('month', v."Bestelldatum") AS Monat,
    SUM(v."Menge" * p."ProduktPreis")     AS Monatsumsatz,
    COUNT(v."BestellID")                  AS Anzahl_Bestellungen
FROM verkaeufe v
JOIN produkte p ON v."ProduktID" = p."ProduktID"
GROUP BY Monat
ORDER BY Monatsumsatz DESC;


-- ------------------------------------------------------------
-- Insight 3: Kundensegmentierung
-- ------------------------------------------------------------
-- CASE WHEN klassifiziert Kunden direkt in der Abfrage.
-- Ergebnis: 20% der Kunden (6 von 30) haben nur einmal bestellt.

SELECT
    k."KundeVorname",
    k."KundeNachname",
    COUNT(v."BestellID")              AS Anzahl_Bestellungen,
    SUM(v."Menge" * p."ProduktPreis") AS Gesamtumsatz,
    CASE
        WHEN COUNT(v."BestellID") = 1  THEN 'Einmalkäufer'
        WHEN COUNT(v."BestellID") <= 3 THEN 'Gelegentlich'
        ELSE 'Stammkunde'
    END AS Kundensegment
FROM kunden k
JOIN verkaeufe v ON k."KundenID"  = v."KundenID"
JOIN produkte  p ON v."ProduktID" = p."ProduktID"
GROUP BY k."KundenID", k."KundeVorname", k."KundeNachname"
ORDER BY Anzahl_Bestellungen DESC;


-- ------------------------------------------------------------
-- Insight 4: Top-Produkt pro Kategorie (Window Function)
-- ------------------------------------------------------------
-- RANK() OVER (PARTITION BY) ordnet Produkte innerhalb
-- jeder Kategorie -- ohne separate Subquery pro Kategorie.

SELECT
    Kategorie,
    ProduktName,
    Gesamtumsatz,
    Rang
FROM (
    SELECT
        k."Kategorie",
        p."ProduktName",
        SUM(v."Menge" * p."ProduktPreis") AS Gesamtumsatz,
        RANK() OVER (
            PARTITION BY k."Kategorie"
            ORDER BY SUM(v."Menge" * p."ProduktPreis") DESC
        ) AS Rang
    FROM verkaeufe v
    JOIN produkte      p ON v."ProduktID"       = p."ProduktID"
    JOIN prodkategorie k ON p."ProdkategorieID" = k."ProdkategorieID"
    GROUP BY k."Kategorie", p."ProduktName"
) ranked
WHERE Rang = 1
ORDER BY Gesamtumsatz DESC;


-- ------------------------------------------------------------
-- Insight 5: Kunden mit überdurchschnittlichem Bestellwert
-- ------------------------------------------------------------
-- HAVING filtert Gruppen nach der Aggregation.
-- Subquery berechnet den Gesamtdurchschnitt dynamisch.

SELECT
    k."KundeVorname",
    k."KundeNachname",
    k."KundeOrt",
    ROUND(AVG(v."Menge" * p."ProduktPreis"), 2) AS Durchschnitt_pro_Bestellung
FROM kunden k
JOIN verkaeufe v ON k."KundenID"  = v."KundenID"
JOIN produkte  p ON v."ProduktID" = p."ProduktID"
GROUP BY k."KundenID", k."KundeVorname", k."KundeNachname", k."KundeOrt"
HAVING AVG(v."Menge" * p."ProduktPreis") > (
    SELECT AVG(v2."Menge" * p2."ProduktPreis")
    FROM verkaeufe v2
    JOIN produkte p2 ON v2."ProduktID" = p2."ProduktID"
)
ORDER BY Durchschnitt_pro_Bestellung DESC;


-- ------------------------------------------------------------
-- Insight 6: Umsatzanteil pro Kategorie in Prozent
-- ------------------------------------------------------------
-- SUM() OVER () ohne PARTITION berechnet den Gesamtumsatz
-- als Fenster -- prozentualer Anteil ohne zusätzlichen Subquery.

SELECT
    k."Kategorie",
    SUM(v."Menge" * p."ProduktPreis") AS Umsatz,
    ROUND(
        100.0 * SUM(v."Menge" * p."ProduktPreis")
        / SUM(SUM(v."Menge" * p."ProduktPreis")) OVER (),
        1
    ) AS Anteil_Prozent
FROM verkaeufe v
JOIN produkte      p ON v."ProduktID"       = p."ProduktID"
JOIN prodkategorie k ON p."ProdkategorieID" = k."ProdkategorieID"
GROUP BY k."Kategorie"
ORDER BY Umsatz DESC;

SET ROLE NONE;
