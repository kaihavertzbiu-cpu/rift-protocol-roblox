-- Chapter-one enemy definitions from the production blueprint.
local Enemies = {}

Enemies.Knight = {
	Name = "RIFTBOUND KNIGHT", HP = 480, ATK = 32, DEF = 10, Poise = 80,
	MoveSpeed = 9, AttackRange = 5.8, AttackCooldown = 1.35,
	Telegraph = .34, Scale = 1.0, Role = "Melee",
}

Enemies.Archer = {
	Name = "ASH ARCHER", HP = 340, ATK = 34, DEF = 5, Poise = 55,
	MoveSpeed = 10, AttackRange = 25, AttackCooldown = 2.25,
	Telegraph = .75, Scale = .92, Role = "Ranged",
}

Enemies.Brute = {
	Name = "BULWARK BRUTE", HP = 1050, ATK = 58, DEF = 22, Poise = 160,
	MoveSpeed = 6.2, AttackRange = 7, AttackCooldown = 2.65,
	Telegraph = .85, Scale = 1.27, Role = "Heavy",
}

Enemies.Warden = {
	Name = "ASHEN WARDEN", HP = 5200, ATK = 65, DEF = 30, Poise = 300,
	MoveSpeed = 7.5, AttackRange = 8, AttackCooldown = 2.0,
	Telegraph = .64, Scale = 1.55, Role = "Boss",
}

return Enemies
