extends RefCounted

const VALID_MODES := ["安静", "活泼", "捣乱"]
const DEFAULT_BEHAVIOR := {
	"modes": {
		"安静": {
			"interval": [4.0, 8.0],
			"actions": [],
		},
		"活泼": {
			"interval": [4.0, 8.0],
			"actions": [
				{"type": "action", "name": "walk", "weight": 34.0},
				{"type": "action", "name": "idle", "weight": 18.0},
				{"type": "action", "name": "edge", "weight": 14.0},
				{"type": "action", "name": "invite", "weight": 14.0},
				{"type": "effect", "name": "footprint", "weight": 20.0},
			],
		},
		"捣乱": {
			"interval": [20.0, 40.0],
			"initial_delay": 1.0,
			"actions": [
				{"type": "mischief", "name": "grab", "weight": 1.0},
			],
		},
	},
	"companion": {
		"tick_seconds": 60.0,
		"cooldowns": {
			"安静": 600.0,
			"活泼": 120.0,
			"捣乱": 300.0,
		},
		"work_cooldown_multiplier": 3.0,
		"adaptation": {
			"enabled": true,
			"strength": "visible",
			"active_cooldown_multiplier_range": [0.55, 1.65],
			"mischief_cooldown_multiplier_range": [0.50, 1.80],
			"weight_multiplier_range": [0.25, 2.75],
		},
	},
}
