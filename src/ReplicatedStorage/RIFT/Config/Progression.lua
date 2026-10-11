local Progression = {}

-- Source-derived talent increments (nodes 15–20), with costs scaled for a short Roblox loop.
Progression.Mastery = {
	{HP = 23, ATK = 0,  DEF = 0, Cost = 149},
	{HP = 0,  ATK = 8,  DEF = 0, Cost = 153},
	{HP = 0,  ATK = 0,  DEF = 2, Cost = 157},
	{HP = 48, ATK = 0,  DEF = 0, Cost = 161},
	{HP = 0,  ATK = 14, DEF = 0, Cost = 165},
	{HP = 0,  ATK = 0,  DEF = 6, Cost = 169},
}

-- Assault Core, source values from the original Core/Magatama curve.
Progression.AssaultCoreATK = {15, 31, 49, 99, 148}
Progression.CoreShardCosts = {1, 2, 6, 18, 54}

Progression.MissionRewards = {
	Credits = 300,
	Shards = 4,
	FirstClearCredits = 80,
}

return Progression

