local EnemyConfig = {}

EnemyConfig.Drone = {
	Name = "Drone I",

	Type = "Normal",

	ATK = 90,
	DEF = 40,
	HP = 1305,

	MoveSpeed = 10,

	AttackRange = 4,
	AttackCooldown = 1.5,
}

EnemyConfig.Striker = {
	Name = "Striker",

	Type = "Normal",

	ATK = 126,
	DEF = 40,
	HP = 1566,

	MoveSpeed = 12,

	AttackRange = 5,
	AttackCooldown = 1.3,
}

EnemyConfig.EliteStriker = {
	Name = "Elite Striker",

	Type = "Elite",

	ATK = 162,
	DEF = 40,
	HP = 1957.5,

	MoveSpeed = 11,

	AttackRange = 5,
	AttackCooldown = 1.2,
}

EnemyConfig.RiftGuardian = {
	Name = "Rift Guardian",

	Type = "Boss",

	ATK = 180,
	DEF = 40,
	HP = 25520,

	MoveSpeed = 8,

	AttackRange = 6,
	AttackCooldown = 1.5,
}

return EnemyConfig