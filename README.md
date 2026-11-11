# Target Loot (Journal)

A small World of Warcraft **3.3.5 (WotLK, Interface 30300)** addon that puts a button on your target showing what
that creature drops — straight from your realm's loot tables. Drops from the creature itself are listed apart from
shared world drops.

## ⚠️ Requires a server-side module

The addon only *displays* loot data; the data has to come from the server. You must install this fork of the
journal server module:

**https://github.com/ScheKaa/wow-mod-forever-journal**

Without it the addon has nothing to show.

## Installation

1. Install the required server module (link above) on your private server.
2. Copy the `TargetLootJournal` folder into `Interface/AddOns/`.
3. Start the client (or `/reload`).

## Usage

- A small button appears on your target — click it, or type `/tloot`, to open the loot list.
- Hover an item for its tooltip.
- Shift-click an item to link it in chat.
- Ctrl-click an item to preview it in the dressing room.

Settings are stored in the `TargetLootJournalDB` saved variable.

## Notes

- **This addon was entirely vibe coded.** It was written by an AI assistant in conversation, from the addon's
  behaviour being described and iterated on — not hand-authored line by line. Expect it to work, but treat the code
  as AI-written rather than meticulously reviewed.
- Server-side foundation (original project): **https://github.com/buildthehomelab/wow-mod-forever-journal**
- Inspiration: **https://www.curseforge.com/wow/addons/target-loot**

## License

MIT — see [LICENSE](LICENSE).
