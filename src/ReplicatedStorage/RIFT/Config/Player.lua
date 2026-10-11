local Player = {}

Player.Base = {
	Level = 1,
	ATK = 50,
	DEF = 20,
	HP = 500,
	CritChance = 0.05,
	CritDamage = 1.50,
}

-- Audited source-derived Lv20 reference retained for progression mapping.
Player.SourceReferenceLv20 = {ATK = 663.1518, DEF = 167.1466, HP = 2238.731}

return Player
