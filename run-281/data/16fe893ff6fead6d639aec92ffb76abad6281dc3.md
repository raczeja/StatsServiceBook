# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: stats.spec.mjs >> stats-section-order >> order-restored-after-reload
- Location: stats.spec.mjs:1214:3

# Error details

```
Error: after reload, expected "records" first, got "last-year"

expect(received).toBe(expected) // Object.is equality

Expected: "records"
Received: "last-year"
```

# Page snapshot

```yaml
- generic [active] [ref=f1e1]:
  - generic [ref=f1e2]:
    - heading "My Stats" [level=1] [ref=f1e14]
    - button "🌙" [ref=f1e15] [cursor=pointer]
  - generic [ref=f1e16]:
    - link "← My Activities" [ref=f1e17] [cursor=pointer]:
      - /url: index.html
    - link "🔧 Bike service" [ref=f1e18] [cursor=pointer]:
      - /url: bike.html
    - link "🗺 Heatmap" [ref=f1e19] [cursor=pointer]:
      - /url: heatmap.html
    - link "📋 Data completeness" [ref=f1e20] [cursor=pointer]:
      - /url: data-quality.html
    - link "🏆 Club leaderboard" [ref=f1e21] [cursor=pointer]:
      - /url: ../
  - generic [ref=f1e22]: 30 activities · updated 2026-07-14
  - generic [ref=f1e23]:
    - generic [ref=f1e24]:
      - text: Sport
      - combobox "Sport" [ref=f1e25] [cursor=pointer]:
        - option "All sports"
        - option "Ride" [selected]
        - option "VirtualRide"
        - option "Run"
        - option "Hike"
        - option "Walk"
    - generic [ref=f1e26]:
      - text: Year
      - combobox "Year" [ref=f1e27] [cursor=pointer]:
        - option "All years"
        - option "2026" [selected]
        - option "2025"
  - generic [ref=f1e28]:
    - button "↺ Reset order" [ref=f1e29] [cursor=pointer]
    - generic [ref=f1e30]:
      - heading "⠿ Last 12 months — last 12 months · Ride" [level=2] [ref=f1e31]:
        - generic "Drag to reorder" [ref=f1e32]: ⠿
        - text: Last 12 months — last 12 months · Ride
      - generic [ref=f1e33]:
        - generic [ref=f1e34]:
          - generic [ref=f1e35]: Distance
          - generic [ref=f1e36]: 1 035 km
        - generic [ref=f1e37]:
          - generic [ref=f1e38]: Moving time
          - generic [ref=f1e39]: 55h 25m
        - generic [ref=f1e40]:
          - generic [ref=f1e41]: Elevation
          - generic [ref=f1e42]: 8 247 m
        - generic [ref=f1e43]:
          - generic [ref=f1e44]: Activities
          - generic [ref=f1e45]: "20"
        - generic [ref=f1e46]:
          - generic [ref=f1e47]: Avg km / activity
          - generic [ref=f1e48]: 51.8 km
        - generic [ref=f1e49]:
          - generic [ref=f1e50]: Avg speed
          - generic [ref=f1e51]: 18.7 km/h
    - generic [ref=f1e52]:
      - generic "Drag to reorder" [ref=f1e53]: ⠿
      - generic [ref=f1e54]:
        - generic [ref=f1e55]:
          - generic [ref=f1e56]: Distance
          - generic [ref=f1e57]: 941.3 km
        - generic [ref=f1e58]:
          - generic [ref=f1e59]: Moving time
          - generic [ref=f1e60]: 50h 10m
          - generic [ref=f1e61]: 2.1 days
        - generic [ref=f1e62]:
          - generic [ref=f1e63]: Elevation
          - generic [ref=f1e64]: 7 287 m
        - generic [ref=f1e65]:
          - generic [ref=f1e66]: Activities
          - generic [ref=f1e67]: "18"
          - generic [ref=f1e68]: 18 / 283 days
        - generic [ref=f1e69]:
          - generic [ref=f1e70]: Avg km / week
          - generic [ref=f1e71]: 23.0 km
        - generic [ref=f1e72]:
          - generic [ref=f1e73]: Avg km / activity
          - generic [ref=f1e74]: 52.3 km
        - generic [ref=f1e75]:
          - generic [ref=f1e76]: Avg speed
          - generic [ref=f1e77]: 18.8 km/h
    - generic [ref=f1e78]:
      - generic "Drag to reorder" [ref=f1e79]: ⠿
      - generic [ref=f1e80]:
        - heading "Annual Goals & Progress — 2026 · Ride" [level=2] [ref=f1e81]:
          - text: Annual Goals & Progress
          - generic [ref=f1e82]: — 2026 · Ride
        - generic [ref=f1e83]:
          - generic [ref=f1e84]:
            - generic [ref=f1e85]:
              - text: Yearly target
              - spinbutton "Yearly target km" [ref=f1e86]: "2000"
              - text: km
            - button "Save" [ref=f1e87] [cursor=pointer]
          - generic [ref=f1e88]:
            - text: 941.3 km of 2 000 km —
            - strong [ref=f1e89]: 47%
            - text: · projected
            - strong [ref=f1e90]: 1 214 km
            - text: (61%)
          - generic [ref=f1e93]: 1 059 km remaining · need 12.9 km/day to finish
          - generic [ref=f1e94]:
            - generic [ref=f1e95]:
              - generic [ref=f1e96]: Jan
              - generic [ref=f1e99]: 60.5 / 166.7
            - generic [ref=f1e100]:
              - generic [ref=f1e101]: Feb
              - generic [ref=f1e104]: 113.5 / 166.7
            - generic [ref=f1e105]:
              - generic [ref=f1e106]: Mar
              - generic [ref=f1e109]: 19.8 / 166.7
            - generic [ref=f1e110]:
              - generic [ref=f1e111]: Apr
              - generic [ref=f1e114]: 194.2 / 166.7
            - generic [ref=f1e115]:
              - generic [ref=f1e116]: May
              - generic [ref=f1e119]: 164.9 / 166.7
            - generic [ref=f1e120]:
              - generic [ref=f1e121]: Jun
              - generic [ref=f1e124]: 303.8 / 166.7
            - generic [ref=f1e125]:
              - generic [ref=f1e126]: Jul
              - generic [ref=f1e129]: 84.6 / 166.7
            - generic [ref=f1e130]:
              - generic [ref=f1e131]: Aug
              - generic [ref=f1e133]: 0.0 / 64.8
            - generic [ref=f1e134]:
              - generic [ref=f1e135]: Sep
              - generic [ref=f1e137]: 0.0 / 278.1
            - generic [ref=f1e138]:
              - generic [ref=f1e139]: OctNOW
              - generic [ref=f1e141]: 0.0 / 272.5
            - generic [ref=f1e142]:
              - generic [ref=f1e143]: Nov
              - generic [ref=f1e145]: 0.0 / 127.8
            - generic [ref=f1e146]:
              - generic [ref=f1e147]: Dec
              - generic [ref=f1e149]: 0.0 / 90.1
    - generic [ref=f1e150]:
      - generic "Drag to reorder" [ref=f1e151]: ⠿
      - generic [ref=f1e152]:
        - heading "Weekly progress — July 2026 · Ride km ‹ ›" [level=2] [ref=f1e153]:
          - text: Weekly progress
          - generic [ref=f1e154]: — July 2026 · Ride km
          - button "‹" [ref=f1e155] [cursor=pointer]
          - button "›" [ref=f1e156] [cursor=pointer]
        - generic [ref=f1e158]:
          - generic "Week 27 · 2026-06-29 · 0.0 / 37.7 km" [ref=f1e159]:
            - generic [ref=f1e160]: W27 · 29/06
            - generic [ref=f1e162]: 0.0 / 37.7
          - generic "Week 28 · 2026-07-06 · 84.6 / 37.7 km" [ref=f1e163]:
            - generic [ref=f1e164]: W28 · 06/07
            - generic [ref=f1e167]: 84.6 / 37.7
          - generic "Week 29 · 2026-07-13 · 0.0 / 37.7 km" [ref=f1e168]:
            - generic [ref=f1e169]: W29 · 13/07
            - generic [ref=f1e171]: 0.0 / 37.7
          - generic "Week 30 · 2026-07-20 · 0.0 / 37.7 km" [ref=f1e172]:
            - generic [ref=f1e173]: W30 · 20/07
            - generic [ref=f1e175]: 0.0 / 37.7
          - generic "Week 31 · 2026-07-27 · 0.0 / 37.7 km" [ref=f1e176]:
            - generic [ref=f1e177]: W31 · 27/07
            - generic [ref=f1e179]: 0.0 / 37.7
    - generic [ref=f1e180]:
      - heading "⠿ Personal records — all time · Ride" [level=2] [ref=f1e181]:
        - generic "Drag to reorder" [ref=f1e182]: ⠿
        - text: Personal records — all time · Ride
      - generic [ref=f1e183]:
        - generic [ref=f1e184]:
          - generic [ref=f1e185]: Longest distance
          - generic [ref=f1e186]: 102.4 km
          - generic [ref=f1e187]: 2026-04-26 4h 23m Spring Century
          - link "View activity →" [ref=f1e189] [cursor=pointer]:
            - /url: activity.html?id=10
        - generic [ref=f1e190]:
          - generic [ref=f1e191]: Longest ride
          - generic [ref=f1e192]: 5h 07m
          - generic [ref=f1e193]: 2026-07-12 84.6 km Magene C606
          - link "View activity →" [ref=f1e195] [cursor=pointer]:
            - /url: activity.html?id=magene-2026-07-12-50671559
        - generic [ref=f1e196]:
          - generic [ref=f1e197]: Most elevation
          - generic [ref=f1e198]: 1 320 m
          - generic [ref=f1e199]: 2026-04-26 102.4 km Spring Century
          - link "View activity →" [ref=f1e201] [cursor=pointer]:
            - /url: activity.html?id=10
        - generic [ref=f1e202]:
          - generic [ref=f1e203]: Longest climb
          - generic [ref=f1e204]: 45 m
          - generic [ref=f1e205]: 2026-07-12 84.6 km Magene C606
          - link "View activity →" [ref=f1e207] [cursor=pointer]:
            - /url: activity.html?id=magene-2026-07-12-50671559
        - generic [ref=f1e208]:
          - generic [ref=f1e209]: Fastest avg speed
          - generic [ref=f1e210]: 25.0 km/h
          - generic [ref=f1e211]: 2026-04-15 50.0 km Spring Spin
          - link "View activity →" [ref=f1e213] [cursor=pointer]:
            - /url: activity.html?id=11
        - generic [ref=f1e214]:
          - generic [ref=f1e215]: Max speed
          - generic [ref=f1e216]: 70.0 km/h
          - generic [ref=f1e217]: 2026-04-26 102.4 km Spring Century
          - link "View activity →" [ref=f1e219] [cursor=pointer]:
            - /url: activity.html?id=10
        - generic [ref=f1e220]:
          - generic [ref=f1e221]: Best VAM
          - generic [ref=f1e222]: 315 m/h
          - generic [ref=f1e223]: 2026-05-24 980 m elev Weekend Climb
          - link "View activity →" [ref=f1e225] [cursor=pointer]:
            - /url: activity.html?id=6
        - generic [ref=f1e226]:
          - generic [ref=f1e227]: Highest estimated HR effort
          - generic [ref=f1e228]: 70 (est.)
          - generic [ref=f1e229]: Estimated from average HR · 2026-06-04 64.3 km West Wroclaw Sample Ride
          - link "View activity →" [ref=f1e231] [cursor=pointer]:
            - /url: activity.html?id=18784255013
        - generic [ref=f1e232]:
          - generic [ref=f1e233]: Best week (km)
          - generic [ref=f1e234]: 140.3 km
          - generic [ref=f1e235]: week of 2026-06-01
          - link "View activities →" [ref=f1e237] [cursor=pointer]:
            - /url: index.html
        - generic [ref=f1e238]:
          - generic [ref=f1e239]: Best month (km)
          - generic [ref=f1e240]: 303.8 km
          - generic [ref=f1e241]: June 2026
          - link "View activities →" [ref=f1e243] [cursor=pointer]:
            - /url: index.html
        - generic [ref=f1e244]:
          - generic [ref=f1e245]: Most activities
          - generic [ref=f1e246]: 6 activities
          - generic [ref=f1e247]: June 2026
          - link "View activities →" [ref=f1e249] [cursor=pointer]:
            - /url: index.html
        - generic [ref=f1e250]:
          - generic [ref=f1e251]: Longest streak
          - generic [ref=f1e252]: 2 days
          - generic [ref=f1e253]: 2026-06-03 → 2026-06-04
          - link "View activities →" [ref=f1e255] [cursor=pointer]:
            - /url: index.html
    - generic [ref=f1e256]:
      - heading "⠿ Top 2 — Longest climb Longest climb (≥ 25 m gain · ≥ 3% grade · 100 m min)" [level=2] [ref=f1e257]:
        - generic "Drag to reorder" [ref=f1e258]: ⠿
        - text: Top 2 — Longest climb
        - combobox [ref=f1e259] [cursor=pointer]:
          - option "Distance"
          - option "Moving time"
          - option "Elevation"
          - option "Avg speed"
          - option "Max speed"
          - option "Power (W)"
          - option "Work (kJ)"
          - option "VAM"
          - option "Longest climb" [selected]
          - option "Steps (walk)"
          - option "Strava Relative Effort"
          - option "Estimated HR effort"
        - text: (≥ 25 m gain · ≥ 3% grade · 100 m min)
      - table [ref=f1e262]:
        - rowgroup [ref=f1e263]:
          - row [ref=f1e264]:
            - columnheader "#" [ref=f1e265]
            - columnheader "Date" [ref=f1e266]
            - columnheader "Activity" [ref=f1e267]
            - columnheader "Longest climb" [ref=f1e268]
            - columnheader "Distance" [ref=f1e269]
            - columnheader "Time" [ref=f1e270]
            - columnheader [ref=f1e271]
        - rowgroup [ref=f1e272]:
          - row [ref=f1e273]:
            - cell "1" [ref=f1e274]
            - cell "2026-07-12" [ref=f1e275]
            - cell "Magene C606" [ref=f1e276]
            - cell "45 m" [ref=f1e277]
            - cell "84.6 km" [ref=f1e278]
            - cell "5h 07m" [ref=f1e279]
            - cell [ref=f1e280]:
              - link "View →" [ref=f1e281] [cursor=pointer]:
                - /url: activity.html?id=magene-2026-07-12-50671559
          - row [ref=f1e282]:
            - cell "2" [ref=f1e283]
            - cell "2026-06-22" [ref=f1e284]
            - cell "CYCLING" [ref=f1e285]
            - cell "38 m" [ref=f1e286]
            - cell "25.1 km" [ref=f1e287]
            - cell "1h 33m" [ref=f1e288]
            - cell [ref=f1e289]:
              - link "View →" [ref=f1e290] [cursor=pointer]:
                - /url: activity.html?id=2026-06-22-10-30-cycling
    - generic [ref=f1e291]:
      - heading "⠿ Year overview" [level=2] [ref=f1e292]:
        - generic "Drag to reorder" [ref=f1e293]: ⠿
        - text: Year overview
      - table [ref=f1e295]:
        - rowgroup [ref=f1e296]:
          - row [ref=f1e297]:
            - columnheader "Year" [ref=f1e298]
            - columnheader "Activities" [ref=f1e299]
            - columnheader "Distance" [ref=f1e300]
            - columnheader "Time" [ref=f1e301]
            - columnheader "Elevation" [ref=f1e302]
            - columnheader "Avg dist" [ref=f1e303]
            - columnheader "Avg speed" [ref=f1e304]
        - rowgroup [ref=f1e305]:
          - row [ref=f1e306]:
            - cell "2026 NOW" [ref=f1e307]:
              - text: "2026"
              - generic [ref=f1e308]: NOW
            - cell "18" [ref=f1e309]
            - cell "941.3 km" [ref=f1e310]
            - cell "50h 10m" [ref=f1e311]
            - cell "7 287 m" [ref=f1e312]
            - cell "52.3 km" [ref=f1e313]
            - cell "18.8 km/h" [ref=f1e314]
          - row [ref=f1e315]:
            - cell "2025" [ref=f1e316]
            - cell "7" [ref=f1e317]
            - cell "359.9 km" [ref=f1e318]
            - cell "20h 26m" [ref=f1e319]
            - cell "4 290 m" [ref=f1e320]
            - cell "51.4 km" [ref=f1e321]
            - cell "17.6 km/h" [ref=f1e322]
    - generic [ref=f1e323]:
      - heading "⠿ Monthly breakdown — 2026" [level=2] [ref=f1e324]:
        - generic "Drag to reorder" [ref=f1e325]: ⠿
        - text: Monthly breakdown — 2026
      - generic [ref=f1e326]:
        - heading "Distance per month (km) — 2026" [level=3] [ref=f1e327]
        - img [ref=f1e328]:
          - generic [ref=f1e330]: "60.5"
          - generic [ref=f1e331]: Jan
          - generic [ref=f1e333]: "113.5"
          - generic [ref=f1e334]: Feb
          - generic [ref=f1e336]: Mar
          - generic [ref=f1e338]: "194.2"
          - generic [ref=f1e339]: Apr
          - generic [ref=f1e341]: "164.9"
          - generic [ref=f1e342]: May
          - generic [ref=f1e344]: "303.8"
          - generic [ref=f1e345]: Jun
          - generic [ref=f1e347]: "84.6"
          - generic [ref=f1e348]: Jul
          - generic [ref=f1e349]: Aug
          - generic [ref=f1e350]: Sep
          - generic [ref=f1e351]: Oct
          - generic [ref=f1e352]: Nov
          - generic [ref=f1e353]: Dec
    - generic [ref=f1e354]:
      - generic "Drag to reorder" [ref=f1e355]: ⠿
      - table [ref=f1e357]:
        - rowgroup [ref=f1e358]:
          - row [ref=f1e359]:
            - columnheader "Month" [ref=f1e360]
            - columnheader "Activities" [ref=f1e361]
            - columnheader "Distance" [ref=f1e362]
            - columnheader "Time" [ref=f1e363]
            - columnheader "Elevation" [ref=f1e364]
            - columnheader "Avg dist" [ref=f1e365]
        - rowgroup [ref=f1e366]:
          - row [ref=f1e367]:
            - cell "January" [ref=f1e368]
            - cell "1" [ref=f1e369]
            - cell "60.5 km" [ref=f1e370]
            - cell "2h 53m" [ref=f1e371]
            - cell "420 m" [ref=f1e372]
            - cell "60.5 km" [ref=f1e373]
          - row [ref=f1e374]:
            - cell "February" [ref=f1e375]
            - cell "2" [ref=f1e376]
            - cell "113.5 km" [ref=f1e377]
            - cell "6h 46m" [ref=f1e378]
            - cell "1 120 m" [ref=f1e379]
            - cell "56.8 km" [ref=f1e380]
          - row [ref=f1e381]:
            - cell "March" [ref=f1e382]
            - cell "1" [ref=f1e383]
            - cell "19.8 km" [ref=f1e384]
            - cell "0h 52m" [ref=f1e385]
            - cell "48 m" [ref=f1e386]
            - cell "19.8 km" [ref=f1e387]
          - row [ref=f1e388]:
            - cell "April" [ref=f1e389]
            - cell "3" [ref=f1e390]
            - cell "194.2 km" [ref=f1e391]
            - cell "9h 11m" [ref=f1e392]
            - cell "2 130 m" [ref=f1e393]
            - cell "64.7 km" [ref=f1e394]
          - row [ref=f1e395]:
            - cell "May" [ref=f1e396]
            - cell "4" [ref=f1e397]
            - cell "164.9 km" [ref=f1e398]
            - cell "8h 38m" [ref=f1e399]
            - cell "1 770 m" [ref=f1e400]
            - cell "41.2 km" [ref=f1e401]
          - row [ref=f1e402]:
            - cell "June" [ref=f1e403]
            - cell "6" [ref=f1e404]
            - cell "303.8 km" [ref=f1e405]
            - cell "16h 41m" [ref=f1e406]
            - cell "1 496 m" [ref=f1e407]
            - cell "50.6 km" [ref=f1e408]
          - row [ref=f1e409]:
            - cell "July" [ref=f1e410]
            - cell "1" [ref=f1e411]
            - cell "84.6 km" [ref=f1e412]
            - cell "5h 07m" [ref=f1e413]
            - cell "303 m" [ref=f1e414]
            - cell "84.6 km" [ref=f1e415]
    - generic [ref=f1e416]:
      - heading "⠿ Year comparison — km per month" [level=2] [ref=f1e417]:
        - generic "Drag to reorder" [ref=f1e418]: ⠿
        - text: Year comparison — km per month
      - table [ref=f1e420]:
        - rowgroup [ref=f1e421]:
          - row [ref=f1e422]:
            - columnheader "Month" [ref=f1e423]
            - columnheader "YoY" [ref=f1e424]
            - columnheader "2026" [ref=f1e425]
            - columnheader "2025" [ref=f1e426]
        - rowgroup [ref=f1e427]:
          - row [ref=f1e428]:
            - cell "Jan" [ref=f1e429]
            - cell "+60.5 km +0.0%" [ref=f1e430]: +60.5 km+0.0%
            - cell "60.5" [ref=f1e431]
            - cell "—" [ref=f1e432]
          - row [ref=f1e433]:
            - cell "Feb" [ref=f1e434]
            - cell "+113.5 km +0.0%" [ref=f1e435]: +113.5 km+0.0%
            - cell "113.5" [ref=f1e436]
            - cell "—" [ref=f1e437]
          - row [ref=f1e438]:
            - cell "Mar" [ref=f1e439]
            - cell "+19.8 km +0.0%" [ref=f1e440]: +19.8 km+0.0%
            - cell "19.8" [ref=f1e441]
            - cell "—" [ref=f1e442]
          - row [ref=f1e443]:
            - cell "Apr" [ref=f1e444]
            - cell "+194.2 km +0.0%" [ref=f1e445]: +194.2 km+0.0%
            - cell "194.2" [ref=f1e446]
            - cell "—" [ref=f1e447]
          - row [ref=f1e448]:
            - cell "May" [ref=f1e449]
            - cell "+164.9 km +0.0%" [ref=f1e450]: +164.9 km+0.0%
            - cell "164.9" [ref=f1e451]
            - cell "—" [ref=f1e452]
          - row [ref=f1e453]:
            - cell "Jun" [ref=f1e454]
            - cell "+303.8 km +0.0%" [ref=f1e455]: +303.8 km+0.0%
            - cell "303.8" [ref=f1e456]
            - cell "—" [ref=f1e457]
          - row [ref=f1e458]:
            - cell "Jul" [ref=f1e459]
            - cell "+84.6 km +0.0%" [ref=f1e460]: +84.6 km+0.0%
            - cell "84.6" [ref=f1e461]
            - cell "—" [ref=f1e462]
          - row [ref=f1e463]:
            - cell "Aug" [ref=f1e464]
            - cell "-28.0 km -100.0%" [ref=f1e465]: "-28.0 km-100.0%"
            - cell "—" [ref=f1e466]
            - cell "28.0" [ref=f1e467]
          - row [ref=f1e468]:
            - cell "Sep" [ref=f1e469]
            - cell "-120.1 km -100.0%" [ref=f1e470]: "-120.1 km-100.0%"
            - cell "—" [ref=f1e471]
            - cell "120.1" [ref=f1e472]
          - row [ref=f1e473]:
            - cell "Oct NOW" [ref=f1e474]:
              - text: Oct
              - generic [ref=f1e475]: NOW
            - cell "-117.7 km -100.0%" [ref=f1e476]: "-117.7 km-100.0%"
            - cell "—" [ref=f1e477]
            - cell "117.7" [ref=f1e478]
          - row [ref=f1e479]:
            - cell "Nov" [ref=f1e480]
            - cell "—" [ref=f1e481]
            - cell "—" [ref=f1e482]
            - cell "55.2" [ref=f1e483]
          - row [ref=f1e484]:
            - cell "Dec" [ref=f1e485]
            - cell "—" [ref=f1e486]
            - cell "—" [ref=f1e487]
            - cell "38.9" [ref=f1e488]
          - row [ref=f1e489]:
            - cell [ref=f1e490]:
              - strong [ref=f1e491]: Total
            - cell [ref=f1e492]:
              - strong [ref=f1e493]: +581.4 km
              - text: +161.5%
            - cell [ref=f1e494]:
              - strong [ref=f1e495]: "941.3"
            - cell [ref=f1e496]:
              - strong [ref=f1e497]: "359.9"
    - generic [ref=f1e498]:
      - heading "⠿ By sport — 2026" [level=2] [ref=f1e499]:
        - generic "Drag to reorder" [ref=f1e500]: ⠿
        - text: By sport — 2026
      - table [ref=f1e502]:
        - rowgroup [ref=f1e503]:
          - row [ref=f1e504]:
            - columnheader "Sport" [ref=f1e505]
            - columnheader "Activities" [ref=f1e506]
            - columnheader "Distance" [ref=f1e507]
            - columnheader "Time" [ref=f1e508]
            - columnheader "Elevation" [ref=f1e509]
            - columnheader "% of km" [ref=f1e510]
        - rowgroup [ref=f1e511]:
          - row [ref=f1e512]:
            - cell "Ride" [ref=f1e513]
            - cell "18" [ref=f1e514]
            - cell "941.3 km" [ref=f1e515]
            - cell "50h 10m" [ref=f1e516]
            - cell "7 287 m" [ref=f1e517]
            - cell "95%" [ref=f1e518]
          - row [ref=f1e519]:
            - cell "VirtualRide" [ref=f1e520]
            - cell "1" [ref=f1e521]
            - cell "30.0 km" [ref=f1e522]
            - cell "1h 00m" [ref=f1e523]
            - cell "0 m" [ref=f1e524]
            - cell "3%" [ref=f1e525]
          - row [ref=f1e526]:
            - cell "Run" [ref=f1e527]
            - cell "2" [ref=f1e528]
            - cell "11.4 km" [ref=f1e529]
            - cell "1h 04m" [ref=f1e530]
            - cell "63 m" [ref=f1e531]
            - cell "1%" [ref=f1e532]
          - row [ref=f1e533]:
            - cell "Walk" [ref=f1e534]
            - cell "1" [ref=f1e535]
            - cell "5.4 km" [ref=f1e536]
            - cell "1h 26m" [ref=f1e537]
            - cell "16 m" [ref=f1e538]
            - cell "1%" [ref=f1e539]
    - generic [ref=f1e540]:
      - heading "⠿ Average per day of week — selected sport · 2026" [level=2] [ref=f1e541]:
        - generic "Drag to reorder" [ref=f1e542]: ⠿
        - text: Average per day of week — selected sport · 2026
      - generic [ref=f1e543]:
        - heading "Avg distance per weekday (km)" [level=3] [ref=f1e544]
        - img [ref=f1e545]:
          - generic [ref=f1e547]: "55.9"
          - generic [ref=f1e548]: Mon
          - generic [ref=f1e550]: "40.2"
          - generic [ref=f1e551]: Tue
          - generic [ref=f1e553]: "52.7"
          - generic [ref=f1e554]: Wed
          - generic [ref=f1e556]: "40.2"
          - generic [ref=f1e557]: Thu
          - generic [ref=f1e559]: "20.0"
          - generic [ref=f1e560]: Fri
          - generic [ref=f1e562]: "56.8"
          - generic [ref=f1e563]: Sat
          - generic [ref=f1e565]: "64.3"
          - generic [ref=f1e566]: Sun
  - generic [ref=f1e567]:
    - text: StravaStats for OpenWrt ·
    - link "activities.json" [ref=f1e568] [cursor=pointer]:
      - /url: activities.json
  - link "StatsServiceBook on GitHub" [ref=f1e570] [cursor=pointer]:
    - /url: https://github.com/raczeja/StatsServiceBook
```

# Test source

```ts
  1125 |     expect(jsErrors.length, jsErrors.map((e) => e.message).join("; ")).toBe(0);
  1126 |   });
  1127 | 
  1128 |   test("all-sections-present", async () => {
  1129 |     const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
  1130 |       els.map((el) => el.getAttribute("data-sid")),
  1131 |     );
  1132 |     const expected = [
  1133 |       "kpis",
  1134 |       "goals",
  1135 |       "weekly-goals",
  1136 |       "records",
  1137 |       "top10",
  1138 |       "year",
  1139 |       "monthly-chart",
  1140 |       "monthly-table",
  1141 |       "comparison",
  1142 |       "sport",
  1143 |       "dow",
  1144 |     ];
  1145 |     expect(sids, `sections: ${JSON.stringify(sids)}`).toEqual(expected);
  1146 |   });
  1147 | 
  1148 |   test("drag-handles-present", async () => {
  1149 |     const n = await page.$$eval(
  1150 |       "#sec-wrap .sec .sec-handle",
  1151 |       (els) => els.length,
  1152 |     );
  1153 |     expect(n, `expected 11 .sec-handle elements, got ${n}`).toBe(11);
  1154 |   });
  1155 | 
  1156 |   test("reset-button-present", async () => {
  1157 |     const n = await page.$$eval(
  1158 |       "#sec-wrap .sec-order-reset",
  1159 |       (els) => els.length,
  1160 |     );
  1161 |     expect(n, `expected 1 .sec-order-reset button, got ${n}`).toBe(1);
  1162 |   });
  1163 | 
  1164 |   test("drag-to-reorder-works", async () => {
  1165 |     await page.evaluate(() => {
  1166 |       const wrap = document.getElementById("sec-wrap");
  1167 |       const secs = Array.from(wrap.querySelectorAll(".sec[data-sid]"));
  1168 |       const src = secs.find((s) => s.getAttribute("data-sid") === "records");
  1169 |       const tgt = secs.find((s) => s.getAttribute("data-sid") === "kpis");
  1170 |       const handle = src ? src.querySelector(".sec-handle") : null;
  1171 |       if (!handle || !tgt) return;
  1172 |       handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
  1173 |       const rect = tgt.getBoundingClientRect();
  1174 |       tgt.dispatchEvent(
  1175 |         new MouseEvent("drop", {
  1176 |           bubbles: true,
  1177 |           cancelable: true,
  1178 |           clientY: rect.top + 1,
  1179 |         }),
  1180 |       );
  1181 |       handle.dispatchEvent(new Event("dragend", { bubbles: true }));
  1182 |     });
  1183 |     await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
  1184 |     const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
  1185 |       els.map((el) => el.getAttribute("data-sid")),
  1186 |     );
  1187 |     expect(
  1188 |       sids[0],
  1189 |       `expected "records" first after drag, got "${sids[0]}"`,
  1190 |     ).toBe("records");
  1191 |     expect(sids[1], `expected "kpis" second after drag, got "${sids[1]}"`).toBe(
  1192 |       "kpis",
  1193 |     );
  1194 |   });
  1195 | 
  1196 |   test("order-persisted-in-localstorage", async () => {
  1197 |     const saved = await page.evaluate(() => {
  1198 |       try {
  1199 |         return JSON.parse(localStorage.getItem("ssb-stats-sec"));
  1200 |       } catch (_) {
  1201 |         return null;
  1202 |       }
  1203 |     });
  1204 |     expect(
  1205 |       Array.isArray(saved) && saved.length === 11,
  1206 |       "saved order should be 11-element array",
  1207 |     ).toBeTruthy();
  1208 |     expect(
  1209 |       saved[0],
  1210 |       `expected "records" first in saved, got "${saved[0]}"`,
  1211 |     ).toBe("records");
  1212 |   });
  1213 | 
  1214 |   test("order-restored-after-reload", async () => {
  1215 |     await page.reload({ waitUntil: "networkidle", timeout: 20000 });
  1216 |     try {
  1217 |       await page.waitForSelector(".sec[data-sid]", { timeout: 10000 });
  1218 |     } catch (_) {}
  1219 |     const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
  1220 |       els.map((el) => el.getAttribute("data-sid")),
  1221 |     );
  1222 |     expect(
  1223 |       sids[0],
  1224 |       `after reload, expected "records" first, got "${sids[0]}"`,
> 1225 |     ).toBe("records");
       |       ^ Error: after reload, expected "records" first, got "last-year"
  1226 |   });
  1227 | 
  1228 |   test("reset-button-restores-default-order", async () => {
  1229 |     await page.evaluate(() => {
  1230 |       const rb = document.querySelector("#sec-wrap .sec-order-reset");
  1231 |       if (rb) rb.click();
  1232 |     });
  1233 |     await page.evaluate(() => new Promise((r) => setTimeout(r, 100)));
  1234 |     const sids = await page.$$eval("#sec-wrap .sec[data-sid]", (els) =>
  1235 |       els.map((el) => el.getAttribute("data-sid")),
  1236 |     );
  1237 |     expect(
  1238 |       sids[0],
  1239 |       `after reset, expected "kpis" first, got "${sids[0]}"`,
  1240 |     ).toBe("kpis");
  1241 |     const saved = await page.evaluate(() => {
  1242 |       try {
  1243 |         return localStorage.getItem("ssb-stats-sec");
  1244 |       } catch (_) {
  1245 |         return "x";
  1246 |       }
  1247 |     });
  1248 |     expect(
  1249 |       saved,
  1250 |       `expected localStorage cleared after reset, got: ${saved}`,
  1251 |     ).toBe(null);
  1252 |   });
  1253 | 
  1254 |   test("weekly-goals-section-can-be-reordered", async () => {
  1255 |     await page.evaluate(() => {
  1256 |       const wrap = document.getElementById("sec-wrap");
  1257 |       const sections = Array.from(wrap.querySelectorAll(".sec[data-sid]"));
  1258 |       const weekly = sections.find(
  1259 |         (section) => section.getAttribute("data-sid") === "weekly-goals",
  1260 |       );
  1261 |       const target = sections.find(
  1262 |         (section) => section.getAttribute("data-sid") === "kpis",
  1263 |       );
  1264 |       const handle = weekly?.querySelector(".sec-handle");
  1265 |       if (!handle || !target) return;
  1266 |       handle.dispatchEvent(new Event("dragstart", { bubbles: true }));
  1267 |       const rect = target.getBoundingClientRect();
  1268 |       target.dispatchEvent(
  1269 |         new MouseEvent("drop", {
  1270 |           bubbles: true,
  1271 |           cancelable: true,
  1272 |           clientY: rect.top + 1,
  1273 |         }),
  1274 |       );
  1275 |       handle.dispatchEvent(new Event("dragend", { bubbles: true }));
  1276 |     });
  1277 |     await page.evaluate(
  1278 |       () => new Promise((resolve) => setTimeout(resolve, 100)),
  1279 |     );
  1280 |     const first = await page.$eval("#sec-wrap .sec[data-sid]", (section) =>
  1281 |       section.getAttribute("data-sid"),
  1282 |     );
  1283 |     expect(first).toBe("weekly-goals");
  1284 |   });
  1285 | });
  1286 | 
  1287 | // ── Stats Top 10 ──────────────────────────────────────────────────────────────
  1288 | 
  1289 | test.describe("stats-top10", () => {
  1290 |   let page;
  1291 |   const jsErrors = [];
  1292 | 
  1293 |   test.beforeAll(async ({ browser }) => {
  1294 |     page = await browser.newPage();
  1295 |     page.on("pageerror", (e) => jsErrors.push(e));
  1296 |     await page.evaluate(() => { try { sessionStorage.clear(); } catch (_) {} });
  1297 |     await page.goto(URLS.stats, { waitUntil: "networkidle", timeout: 20000 });
  1298 |     try {
  1299 |       await page.waitForSelector("#top10Table", { timeout: 10000 });
  1300 |       await page.waitForFunction(
  1301 |         () => !document.getElementById("meta")?.textContent.includes("Loading"),
  1302 |         { timeout: 10000 },
  1303 |       );
  1304 |     } catch (_) {}
  1305 |   });
  1306 | 
  1307 |   test.afterAll(async () => { await page.close(); });
  1308 | 
  1309 |   test("no-js-errors", () => {
  1310 |     expect(jsErrors.length, jsErrors.map((e) => e.message).join("; ")).toBe(0);
  1311 |   });
  1312 | 
  1313 |   test("top10-section-exists", async () => {
  1314 |     const el = await page.$('[data-sid="top10"]');
  1315 |     expect(el, 'expected [data-sid="top10"] section to exist').toBeTruthy();
  1316 |   });
  1317 | 
  1318 |   test("top10-select-has-options", async () => {
  1319 |     const n = await page.$$eval("#top10Sel option", (opts) => opts.length);
  1320 |     expect(n >= 5, `expected >= 5 options in #top10Sel, got ${n}`).toBeTruthy();
  1321 |   });
  1322 | 
  1323 |   test("top10-default-metric-is-climb", async () => {
  1324 |     const val = await page.$eval("#top10Sel", (el) => el.value);
  1325 |     expect(val, `expected default metric "climb", got "${val}"`).toBe("climb");
```