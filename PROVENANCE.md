# Provenance

Code in this repository that was copied or ported from another bradbrownjr repository.
When the source changes, check it for fixes worth bringing over; when a file here improves,
offer the change back to the source. Paths are relative to each repository's root;
Source repo is the repository name, Source commit the commit the copy was taken from.

| Local path | Source repo | Source path | Source commit | Copied | Local changes |
|---|---|---|---|---|---|
| `lib/geo.py` | bpq-apps | `apps/predict/geo.py` | 3aba9dc | 2026-10-06 | regions.json path only |
| `lib/ionosphere.py` | bpq-apps | `apps/predict/ionosphere.py` | 802d4f1 | 2026-10-06 | datetime.utcnow() replaced by datetime.now(timezone.utc) |
| `data/regions.json` | bpq-apps | `apps/predict/regions.json` | 3aba9dc | 2026-10-06 | none |
| `lib/formsfmt.py` | bpq-apps | `apps/forms.py` | c2f6ed5 | 2026-10-06 | NTS, strip and PKTNET functions only; Forms class not copied |
| `data/forms/bulletin.frm` | bpq-apps | `apps/forms/bulletin.frm` | eb1dbb2 | 2026-10-06 | none |
| `data/forms/dyfi.frm` | bpq-apps | `apps/forms/dyfi.frm` | e8e4f78 | 2026-10-06 | none |
| `data/forms/eqstat.frm` | bpq-apps | `apps/forms/eqstat.frm` | eb1dbb2 | 2026-10-06 | none |
| `data/forms/fsr.frm` | bpq-apps | `apps/forms/fsr.frm` | eb1dbb2 | 2026-10-06 | none |
| `data/forms/gyx-weather.frm` | bpq-apps | `apps/forms/gyx-weather.frm` | 71d5144 | 2026-10-06 | none |
| `data/forms/ics213.frm` | bpq-apps | `apps/forms/ics213.frm` | eb1dbb2 | 2026-10-06 | none |
| `data/forms/ics309.frm` | bpq-apps | `apps/forms/ics309.frm` | eb1dbb2 | 2026-10-06 | none |
| `data/forms/mcf720-price-survey.frm` | bpq-apps | `apps/forms/mcf720-price-survey.frm` | 8936c46 | 2026-10-06 | none |
| `data/forms/netcheck.frm` | bpq-apps | `apps/forms/netcheck.frm` | a9837c0 | 2026-10-06 | none |
| `data/forms/radiogram.frm` | bpq-apps | `apps/forms/radiogram.frm` | c2f6ed5 | 2026-10-06 | none |
| `data/forms/severe_wx.frm` | bpq-apps | `apps/forms/severe_wx.frm` | eb1dbb2 | 2026-10-06 | none |
| `data/forms/strip.frm` | bpq-apps | `apps/forms/strip.frm` | eb1dbb2 | 2026-10-06 | none |
| `feeds.json` | bpq-apps | `apps/rss-news.conf` | e9dd33b | 2026-10-06 | converted to JSON; 3 dead feeds removed |
| `apps.json` | bpq-apps | `apps/apps.json` | 8ad0e9b | 2026-10-05 | menu restructured for NomadNet |
| `pages/index.mu` | bpq-apps | `apps/apps.py` | 6f5069d | 2026-10-05 | ported to NomadNet micron |
| `pages/wall.mu` | bpq-apps | `apps/wall.py` | 26b9130 | 2026-10-05 | ported to NomadNet micron |
| `pages/hamqsl.mu` | bpq-apps | `apps/hamqsl.py` | fe46395 | 2026-10-05 | ported to NomadNet micron |
| `pages/wx-me.mu` | bpq-apps | `apps/wx-me.py` | 982210d | 2026-10-05 | ported to NomadNet micron |
| `pages/space.mu` | bpq-apps | `apps/space.py` | 982210d | 2026-10-05 | ported to NomadNet micron |
| `pages/wx.mu` | bpq-apps | `apps/wx.py` | 27f9158 | 2026-10-06 | ported to NomadNet micron |
| `pages/dict.mu` | bpq-apps | `apps/dict.py` | 31625ad | 2026-10-06 | ported to NomadNet micron |
| `pages/repeater.mu` | bpq-apps | `apps/repeater.py` | 6f5069d | 2026-10-06 | ported to NomadNet micron |
| `pages/qrz.mu` | bpq-apps | `apps/qrz3.py` | 1a5a2e5 | 2026-10-06 | ported to NomadNet micron |
| `pages/wiki.mu` | bpq-apps | `apps/wiki.py` | 6f5069d | 2026-10-06 | ported to NomadNet micron |
| `pages/news.mu` | bpq-apps | `apps/rss-news.py` | 1a5a2e5 | 2026-10-06 | ported to NomadNet micron |
| `pages/calendar.mu` | bpq-apps | `apps/eventcal.py` | 1a5a2e5 | 2026-10-06 | ported to NomadNet micron |
| `pages/antenna.mu` | bpq-apps | `apps/antenna.py` | 687d723 | 2026-10-06 | ported to NomadNet micron |
| `pages/hamtest.mu` | bpq-apps | `apps/hamtest.py` | 1a5a2e5 | 2026-10-06 | ported to NomadNet micron |
| `pages/predict.mu` | bpq-apps | `apps/predict.py` | eab627a | 2026-10-06 | ported to NomadNet micron |
| `pages/gopher.mu` | bpq-apps | `apps/gopher.py` | 27f9158 | 2026-10-06 | ported to NomadNet micron |
| `pages/www.mu` | bpq-apps | `apps/www.py` | 27f9158 | 2026-10-06 | ported to NomadNet micron |
| `pages/forms.mu` | bpq-apps | `apps/forms.py` | c2f6ed5 | 2026-10-06 | ported to NomadNet micron |

Not listed: `data/question_pools/*.json` match bpq-apps' copies, which are not tracked in git there (the source is the public NCVEC pools). `lib/htmltext.py` does the same job as bpq-apps' HTML stripping but shares no code.
