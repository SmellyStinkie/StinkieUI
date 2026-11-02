StinkieRoleHealer.ttf / StinkieRoleTank.ttf / StinkieRoleDamage.ttf are tiny symbol fonts made for Stinkie UI
(MIT, same as the addon). In the healer font only the character "4" has a glyph (a plus
sign); in the tank font only "1" does (a shield); in the damage font "2" and "8" do (a sword).
Every other character is a speck far below one pixel (WoW draws a box for truly empty glyphs). role_*.tga are the same shapes as textures for readable roles.

Why: during a live PvP match the game hands addons the scoreboard role (1 tank, 2 damage,
4 healer) only as a "secret" number that may be displayed but not compared. Writing that
number as text in these fonts shows a cross for healers and a shield for tanks without the
addon ever reading the value. make_role_fonts.py and make_role_textures.py (with shapes.py) rebuild them (need fontTools / Pillow).
