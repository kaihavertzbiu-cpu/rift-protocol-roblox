-- Server-authoritative chapter-one timing and impact. Coefs use ATK=50.
local Skills = {}

Skills.Basic = {
	Range = 8,
	ComboReset = .75,
	Steps = {
		{Name = "M1-1", Coef = 1.14, Poise = 12, Cooldown = .52, Windup = .14, Active = .10, Recovery = .28},
		{Name = "M1-2", Coef = 1.24, Poise = 14, Cooldown = .56, Windup = .16, Active = .10, Recovery = .30},
		{Name = "M1-3", Coef = 1.65, Poise = 24, Cooldown = .72, Windup = .20, Active = .12, Recovery = .40},
	},
}

Skills.Heavy = {Name = "HEAVY", Coef = 2.48, Poise = 38, Stamina = 18, Cooldown = .88, Windup = .34, Active = .14, Recovery = .40, Range = 9}
Skills.Dodge = {Name = "DODGE", Stamina = 22, Cooldown = .55, IFrame = .18, Duration = .55}
Skills.Q = {Name = "RIFT SLASH", Coef = 3.0, Poise = 28, Cooldown = 7, Range = 24}
Skills.E = {Name = "GUARD BREAK", Coef = 1.76, Poise = 60, Cooldown = 11, Range = 10}

return Skills
