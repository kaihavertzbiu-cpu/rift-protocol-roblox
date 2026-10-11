local SkillConfig = {}

-- Basic Attack / 普通攻击
SkillConfig.BasicAttack = {
	Range = 8,
	ComboResetTime = 1.2,

	Steps = {
		{
			Name = "Basic Attack 1",
			ATKCoef = 0.55,
			Cooldown = 0.35,
		},

		{
			Name = "Basic Attack 2",
			ATKCoef = 0.65,
			Cooldown = 0.35,
		},

		{
			Name = "Basic Attack 3",
			ATKCoef = 0.90,
			Cooldown = 0.55,
		},
	},
}

-- Q Skill / Q技能
SkillConfig.Q = {
	Name = "Pulse Blade",

	ATKCoef = 1.20,
	FlatDamage = 0,

	Cooldown = 4,
	Range = 18,
}

-- E Skill / E技能
SkillConfig.E = {
	Name = "Phase Strike",

	ATKCoef = 0.90,
	FlatDamage = 0,

	Cooldown = 7,
	Range = 12,
}

-- R Skill / 大招
SkillConfig.R = {
	Name = "Core Overload",

	ATKCoef = 2.20,
	FlatDamage = 0,

	Cooldown = 22,
	Range = 14,
}

-- F Skill / Tactical Protocol / 战术模块
SkillConfig.F = {
	Name = "Gravity Field",

	ATKCoef = 1.10,
	FlatDamage = 0,

	Cooldown = 12,
	Range = 16,

	SlowPercent = 0.30,
	SlowDuration = 2,
}

return SkillConfig