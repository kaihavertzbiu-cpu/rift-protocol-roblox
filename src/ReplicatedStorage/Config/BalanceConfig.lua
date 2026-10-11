local BalanceConfig = {}

-- Combat Rating weights from the source combat spreadsheet.
BalanceConfig.CombatRating = {
	ATKWeight = 3.5,
	DEFWeight = 11.6,
	HPWeight = 1.0,
}

-- Demo damage mitigation constant.
-- FinalDamage = RawDamage * K / (K + DEF)
BalanceConfig.DamageDefenseK = 300

return BalanceConfig
