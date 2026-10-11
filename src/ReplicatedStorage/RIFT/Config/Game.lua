local Game = {}

Game.Title = "RIFT PROTOCOL"
Game.Subtitle = "ENTER • ADAPT • ASCEND"

Game.LobbySpawn = CFrame.new(0, 5, 15)
Game.MissionCenter = Vector3.new(0, 2, -420)
Game.MissionSpawn = CFrame.new(0, 5, -380)

-- Product identifiers stay zero in source control. Fill these only after the
-- corresponding Creator Dashboard products exist; no local build may invent
-- an ID or silently grant paid combat power.
Game.Monetization = {
	FounderPassId = 0,
	CosmeticPassId = 0,
	SupporterTipProductId = 0,
	FounderFallbackPrice = 299,
	CosmeticFallbackPrice = 149,
	TipFallbackPrice = 25,
}

Game.Waves = {
	{
		Label = "ASHEN SANCTUM  /  FIRST CONTACT",
		Enemies = {"Knight", "Knight"},
	},
	{
		Label = "ASHEN SANCTUM  /  CROSS-FIRE",
		Enemies = {"Knight", "Archer"},
	},
	{
		Label = "ASHEN SANCTUM  /  BREAK THE BULWARK",
		Enemies = {"Brute", "Knight"},
	},
	{
		Label = "BROKEN CLOISTER  /  ELITE",
		Enemies = {"Brute", "Archer"},
	},
	{
		Label = "ASHEN WARDEN",
		Enemies = {"Warden"},
	},
}

Game.RuneOffers = {
	{
		{Id="EmberEdge", Name="EMBER EDGE", Tag="FIRE", Description="M1 third strike adds 35 fire damage."},
		{Id="ShatterSigil", Name="SHATTER SIGIL", Tag="BREAK", Description="Deal 25% more damage to broken enemies."},
		{Id="ExecutionMark", Name="EXECUTION MARK", Tag="EXECUTE", Description="Deal 18% more damage below 25% enemy HP."},
	},
	{
		{Id="RiftEcho", Name="RIFT ECHO", Tag="RIFT", Description="Skills have a 20% chance to echo for bonus damage."},
		{Id="BloodPact", Name="BLOOD PACT", Tag="RISK", Description="Lose 15% max HP; skill damage +20%."},
		{Id="GuardianRune", Name="GUARDIAN RUNE", Tag="SHIELD", Description="After 3s unharmed, gain a 40 point shield."},
	},
}

return Game
