# The G3223D's PiP/PbP values (VCP 0xE9), mapped at the monitor

Created: 2026-10-29 12:10 -05:00 · Edited: 2026-10-29 12:25 -05:00

Owner at the desk, agent on `monitorctl`, 2026-10-29. The table below is the second pass: each value
set from **Off**, held for seven seconds, read back, and described by the owner. The first pass chained
the values one after another and its reports disagreed with the second for 0x29 (reported "50-50"
when entered from 0x21, "Mac 25 %" when entered from 0x24 and from Off) and for 0x2D (reported "50-50
with HDMI 1" when entered from 0x2A, "Mac 25 %" from Off). Whether the monitor's picture depends on the
previous mode or the first-pass readings were hurried is not known; the from-Off pass is the one
recorded, and setting from Off is the method for any future mapping. No second source was attached: the
secondary pane showed the Dell's "HDMI 1" no-signal label throughout. Every change that took made the
monitor retrain its link (one to two seconds of black; the first read after it fails, RR9).

| Value | Read back | On screen | Label |
|---|---|---|---|
| 0x01 | Off (0x00) within 1 s | nothing; no retrain | ignored by the firmware |
| 0x02 | Off (0x00) within 1 s | nothing; no retrain | ignored by the firmware |
| 0x21 | 0x21 | small inset, upper right | PiP small (m1ddc, confirmed) |
| 0x24 | 0x24 | two equal panes, Mac left | PbP 50/50 (m1ddc, confirmed) |
| 0x29 | 0x29 | Mac 25 % left, secondary 75 % right | PbP 25/75 |
| 0x2A | 0x2A | Mac 75 % left, secondary 25 % right | PbP 75/25 |
| 0x2D | 0x2D | indistinguishable from 0x29 | PbP 25/75 (duplicate) |
| 0x2E | 0x2E | indistinguishable from 0x2A | PbP 75/25 (duplicate) |

Not re-checked: 0x22 (PiP large, m1ddc). Not advertised by this monitor, so never offered: 0x2B, 0x2C,
0x41 from m1ddc's Dell list.

The sub-source register 0xEA read `0xFC01` in Off, 0x24, 0x29 and 0x2D, so it does not
explain the duplicate pairs; the OSD showed the owner no difference either. The pairs most likely
encode a secondary input (Dell lists a mode per sub source in some firmware), which a second attached
source would reveal (`O10`).

Closes `O5` and `RR5` (meaning of the ten values). Corrects nothing in m1ddc's list; extends it.
