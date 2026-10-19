import datetime

# (month, day, year, time(24h H:M), opponent, home_or_away)
games = [
    (10,20,2026,"19:00","Philadelphia 76ers","Home"),
    (10,23,2026,"19:00","Boston Celtics","Away"),
    (10,25,2026,"19:00","Orlando Magic","Home"),
    (10,27,2026,"20:00","Detroit Pistons","Home"),
    (10,28,2026,"20:00","Chicago Bulls","Away"),
    (10,30,2026,"19:30","Philadelphia 76ers","Away"),
    (11,2,2026,"19:30","Brooklyn Nets","Home"),
    (11,4,2026,"19:30","Chicago Bulls","Home"),
    (11,7,2026,"20:00","Cleveland Cavaliers","Away"),
    (11,10,2026,"19:30","Milwaukee Bucks","Home"),
    (11,11,2026,"19:00","Cleveland Cavaliers","Home"),
    (11,13,2026,"19:00","Indiana Pacers","Away"),
    (11,15,2026,"18:00","Toronto Raptors","Away"),
    (11,17,2026,"19:30","Toronto Raptors","Away"),
    (11,19,2026,"20:00","Minnesota Timberwolves","Away"),
    (11,21,2026,"19:30","Portland Trail Blazers","Home"),
    (11,22,2026,"20:00","Indiana Pacers","Home"),
    (11,25,2026,"19:30","Cleveland Cavaliers","Home"),
    (11,27,2026,"19:00","Miami Heat","Home"),
    (11,29,2026,"18:00","Atlanta Hawks","Home"),
    (12,1,2026,"20:00","Chicago Bulls","Away"),
    (12,2,2026,"20:00","Milwaukee Bucks","Away"),
    (12,12,2026,"20:30","Miami Heat","Away"),
    (12,14,2026,"20:30","Houston Rockets","Away"),
    (12,16,2026,"20:00","New Orleans Pelicans","Away"),
    (12,18,2026,"19:00","Washington Wizards","Away"),
    (12,21,2026,"19:00","Cleveland Cavaliers","Away"),
    (12,23,2026,"19:30","Utah Jazz","Home"),
    (12,25,2026,"12:00","San Antonio Spurs","Home"),
    (12,27,2026,"18:00","Brooklyn Nets","Home"),
    (12,30,2026,"21:00","Utah Jazz","Away"),
    (12,31,2026,"21:00","Phoenix Suns","Away"),
    (1,2,2027,"17:00","Denver Nuggets","Away"),
    (1,4,2027,"22:00","Portland Trail Blazers","Away"),
    (1,6,2027,"22:00","Golden State Warriors","Away"),
    (1,8,2027,"22:00","Sacramento Kings","Away"),
    (1,11,2027,"19:30","Denver Nuggets","Home"),
    (1,13,2027,"19:00","Boston Celtics","Away"),
    (1,14,2027,"19:30","Miami Heat","Home"),
    (1,16,2027,"19:30","Dallas Mavericks","Home"),
    (1,18,2027,"17:00","Minnesota Timberwolves","Home"),
    (1,20,2027,"19:30","Toronto Raptors","Home"),
    (1,22,2027,"19:00","Atlanta Hawks","Away"),
    (1,24,2027,"19:00","LA Clippers","Home"),
    (1,26,2027,"19:30","Phoenix Suns","Home"),
    (1,28,2027,"19:00","Atlanta Hawks","Home"),
    (1,30,2027,"20:30","Los Angeles Lakers","Home"),
    (2,1,2027,"19:30","Brooklyn Nets","Away"),
    (2,3,2027,"19:00","Detroit Pistons","Away"),
    (2,4,2027,"19:30","Toronto Raptors","Home"),
    (2,7,2027,"21:30","Oklahoma City Thunder","Away"),
    (2,9,2027,"19:30","Charlotte Hornets","Home"),
    (2,11,2027,"19:00","Philadelphia 76ers","Away"),
    (2,13,2027,"20:30","Golden State Warriors","Home"),
    (2,15,2027,"20:00","Memphis Grizzlies","Away"),
    (2,17,2027,"19:00","Detroit Pistons","Away"),
    (2,25,2027,"19:30","Oklahoma City Thunder","Home"),
    (2,27,2027,"20:30","Philadelphia 76ers","Home"),
    (2,28,2027,"19:30","Milwaukee Bucks","Home"),
    (3,2,2027,"19:30","Memphis Grizzlies","Home"),
    (3,4,2027,"21:30","Dallas Mavericks","Away"),
    (3,7,2027,"19:30","San Antonio Spurs","Away"),
    (3,10,2027,"22:30","LA Clippers","Away"),
    (3,11,2027,"22:00","Los Angeles Lakers","Away"),
    (3,14,2027,"12:00","Boston Celtics","Home"),
    (3,16,2027,"19:00","Washington Wizards","Away"),
    (3,17,2027,"19:30","Sacramento Kings","Home"),
    (3,20,2027,"13:00","Washington Wizards","Home"),
    (3,23,2027,"19:30","New Orleans Pelicans","Home"),
    (3,24,2027,"19:30","Houston Rockets","Home"),
    (3,26,2027,"19:00","Charlotte Hornets","Away"),
    (3,28,2027,"12:30","Orlando Magic","Away"),
    (3,30,2027,"20:00","Orlando Magic","Away"),
    (4,1,2027,"19:30","Charlotte Hornets","Home"),
    (4,2,2027,"19:30","Brooklyn Nets","Away"),
    (4,4,2027,"19:30","Boston Celtics","Home"),
    (4,6,2027,"20:00","Atlanta Hawks","Away"),
    (4,8,2027,"20:00","Milwaukee Bucks","Away"),
    (4,9,2027,"19:00","Detroit Pistons","Home"),
    (4,11,2027,"18:00","Indiana Pacers","Home"),
]

def fmt(dt):
    return dt.strftime("%Y%m%dT%H%M%S")

lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//NYK Schedule//EN",
    "CALSCALE:GREGORIAN",
]

for i, (m, d, y, t, opp, loc) in enumerate(games):
    hh, mm = map(int, t.split(":"))
    start = datetime.datetime(y, m, d, hh, mm)
    end = start + datetime.timedelta(hours=2, minutes=30)
    summary = f"Knicks vs {opp}" if loc == "Home" else f"Knicks @ {opp}"
    location = "Madison Square Garden, New York, NY" if loc == "Home" else opp
    uid = f"nyk-2026-27-{i:03d}@nba-analytics.local"
    lines += [
        "BEGIN:VEVENT",
        f"UID:{uid}",
        f"DTSTAMP:{fmt(datetime.datetime.utcnow())}",
        f"DTSTART;TZID=America/New_York:{fmt(start)}",
        f"DTEND;TZID=America/New_York:{fmt(end)}",
        f"SUMMARY:{summary}",
        f"LOCATION:{location}",
        f"DESCRIPTION:NYK {loc} game vs {opp} - 2026-27 NBA Regular Season",
        "END:VEVENT",
    ]

lines.append("END:VCALENDAR")

with open("web/public/data/../../nyk_2026_27_schedule.ics", "w", newline="\r\n") as f:
    f.write("\r\n".join(lines))

print(f"Wrote {len(games)} games")
