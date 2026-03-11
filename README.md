# Aufbau einer Datenbank aus nicht-normalisierten Daten

End-to-End-Datenbankprojekt: von einer flachen Excel-Tabelle zu einer sicheren, rollenbasierten PostgreSQL-Datenbank mit Python-Analyse.

**Datensatz:** 100 Verkaufsdatensätze · 3 Produktkategorien · Zeitraum: Oktober 2020 – Juni 2023

---

## Technologien

`PostgreSQL` · `pgAdmin 4` · `DBeaver` · `Python` · `pandas` · `SQLAlchemy` · `Jupyter Notebook`

---

## Projektstruktur

```
├── database_setup.sql       # Tabellenerstellung, Rollen, Views, Trigger, Insights
├── sales_analysis.ipynb     # Python-Analyse: Import + Grundfragen + Business-Insights
├── data/
│   ├── prodkategorie.csv
│   ├── produkte.csv
│   ├── kunden.csv
│   └── verkaeufe.csv
├── .env.example             # Vorlage für Datenbankzugangsdaten
├── .gitignore
└── presentation/
    └── Datenbank.pdf
```

---

## Vorgehen

### 1 — Normalisierung

Die ursprüngliche Excel-Tabelle (`03_nicht_normalisierte_Daten.xlsx`) enthielt 9 Spalten in einer einzigen flachen Struktur mit vielen redundanten Werten:

| Spalte | Problem |
|--------|---------|
| `KundeName` | Vor- und Nachname in einem Feld |
| `KundeAdresse` | Straße, PLZ und Ort in einem Feld |
| `Kategorie` | Wiederholt sich bei jedem Produkt |
| `ProduktPreis` | Wiederholt sich bei jeder Bestellung desselben Produkts |

**Lösung — Aufteilung in 4 Tabellen nach 3. Normalform:**

```
prodkategorie (ProdkategorieID, Kategorie)
       ↑
produkte (ProduktID, ProduktName, ProduktPreis, ProdkategorieID)
       ↑
verkaeufe (BestellID, Menge, Bestelldatum, KundenID, ProduktID)
       ↑
kunden (KundenID, KundeVorname, KundeNachname, KundeStrasse,
        KundePostzahl, KundeOrt, KundeKreditkarte)
```

**Designentscheidungen:**
- `prodkategorie` als eigene Tabelle: ermöglicht späteres Erweitern (z. B. Kategoriebeschreibung, Rabatte)
- `KundeName` → `KundeVorname` + `KundeNachname`: sauberere Filterung und Sortierung
- `KundeAdresse` → drei separate Felder: Abfragen nach Stadt oder PLZ möglich
- `KundePostzahl` und `KundeKreditkarte` als `TEXT`: verhindert Verlust führender Nullen

Die ursprüngliche Excel-Tabelle wurde nach den Prinzipien der 3. Normalform in vier Tabellen aufgeteilt: `prodkategorie`, `produkte`, `kunden` und `verkaeufe` mit entsprechenden Primär- und Fremdschlüsselbeziehungen.

### 2 — Import in PostgreSQL
Die Tabellenstruktur wurde per SQL in DBeaver angelegt. Die Daten wurden anschließend mit pandas und SQLAlchemy aus den CSV-Dateien importiert.

### 3 — Rollen & Benutzer
Zwei Rollen mit unterschiedlichen Berechtigungen wurden eingerichtet: `callcenter_mitarbeiter` mit Lesezugriff nur auf den Sicherheits-View, und `datenanalyst` mit Lesezugriff auf alle Tabellen.

### 4 — Sicherheits-View
Um sensible Daten zu schützen, wurde ein View erstellt, der Kreditkartennummern maskiert und nur die letzten 3 Ziffern anzeigt. Der direkte Zugriff auf die Tabelle `kunden` wurde für Call-Center-Mitarbeiter entzogen.

```sql
CREATE VIEW kunden_view_sicher AS
SELECT
    "KundenID", "KundeVorname", "KundeNachname",
    '************* ' || RIGHT("KundeKreditkarte", 3) AS Kreditkarte_letzte3
FROM kunden;
```

### 5 — Datenanalyse
Grundlegende Fragen aus der Aufgabenstellung sowie erweiterte Business-Insights mit `JOIN`, `GROUP BY`, `HAVING`, `CASE WHEN` und Window Functions (`RANK`, `SUM OVER`):

| Frage / Insight | Ergebnis |
|---|---|
| Umsatzstärkster Kunde | Linnet Firmage — 121.378 € |
| Zeitraum der Bestelldaten | Oktober 2020 – Juni 2023 |
| Häufigster Einkaufstag | Mittwoch (21 Bestellungen) |
| Stärkste Kategorie | Uhren — 123.680 € (31% des Gesamtumsatzes) |
| Stärkster Monat | Oktober 2020 — 120.000 € |
| Kundensegmente | 6 Einmalkäufer · 13 Gelegentlich · 11 Stammkunden |
| Top-Produkt je Kategorie | via `RANK() OVER (PARTITION BY Kategorie)` |
| Premium-Kunden | Kunden über dem Gesamtdurchschnitt via `HAVING` |

### 6 — Audit-Trigger
Ein Trigger protokolliert alle Datenänderungen (INSERT, UPDATE, DELETE) auf der Tabelle `kunden` mit Benutzername und Zeitstempel. Da PostgreSQL keine Trigger auf SELECT unterstützt, werden nur Schreiboperationen erfasst.

### 7 — Python-Zugriff mit Rollenbeschränkung
Die Python-Analyse wird als Benutzer `schmidt` mit der Rolle `datenanalyst` ausgeführt. Der Lesezugriff ist auf Datenbankebene erzwungen — Schreiboperationen werden abgelehnt.

---

## Sicherheitshinweis

Passwörter werden nicht im Repository gespeichert. Für den lokalen Betrieb bitte eine `.env`-Datei verwenden und diese in `.gitignore` eintragen:

```python
import os
password = os.environ["DB_PASSWORD"]
```

---

## Fazit

SQL eignet sich ideal für Tabellenstruktur, Schlüsselbeziehungen, Zugriffskontrolle und komplexe Analysen mit Window Functions. pandas übernimmt effizient den Massenimport und die Analyse. Die klare Trennung beider Werkzeuge macht den Workflow nachvollziehbar und sicher. Das Rollenkonzept mit maskierten Kreditkartendaten zeigt praxisnahe Datensicherheit.
