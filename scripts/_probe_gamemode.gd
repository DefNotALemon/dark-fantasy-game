extends Node
## Throwaway probe: does the GameMode class resolve at all?


func probe() -> float:
	return GameMode.heal_rate_mult()
