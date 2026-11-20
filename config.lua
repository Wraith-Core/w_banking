Config = {}
Config.MaxTransaction = 1000000000
Config.ServerDistance = 8.0

-- Bank counters. `name` is the internal id; `label` is the dictionary key
-- (locales/{ar,en}.json) used for the prompt text and the map blip.
Config.BankLocations = {
    { name = 'rhodes',     label = 'bank.rhodes',     coords = vector4(1291.15, -1303.22, 77.04, 318.72),   showblip = true },
    { name = 'lemoyne',    label = 'bank.lemoyne',    coords = vector4(2644.86, -1293.99, 52.25, 20.73),    showblip = true },
    { name = 'valentine',  label = 'bank.valentine',  coords = vector4(-308.16, 773.93, 118.7, 4.16),       showblip = true },
    { name = 'blackwater', label = 'bank.blackwater', coords = vector4(-813.23, -1275.39, 43.64, 180.86),   showblip = true },
}

-- Ped model of the bank clerk and the map blip settings
Config.ClerkModel = 'A_M_M_BiVFancyTravellers_01'
Config.Blip = { sprite = -2128054417, scale = 0.2 }

-- Counter prompt (library NUI prompt): keyboard key name and the radius, in metres, around
-- the spot in front of the clerk where it shows.
Config.Prompt = { key = 'J', distance = 1.5 }

-- Door hashes of the bank buildings: registered with the door system and kept unlocked
-- so the counters can be reached.
Config.BankDoors = {
	-- Valentine Savings Bank
	2642457609, -- main door
	3886827663, -- main door
	1340831050, -- bared right
	2343746133, -- bared left
	334467483, -- inner door1
	3718620420, -- inner door2
	576950805, -- vault door

	-- Bank of Rhodes
	3317756151, -- main door
	3088209306, -- main door
	2058564250, -- inner door1
	3142122679, -- inner door2
	1634148892, -- inner door3
	3483244267, -- vault

	-- Lemoyne National Bank Saint Denis
	2158285782, -- main door
	1733501235, -- main door
	2089945615, -- main door
	2817024187, -- main door
	1830999060, -- inner private door
	965922748, -- manager door
	1634115439, -- manager door
	1751238140, -- vault

	-- West Elizabeth Co-Operative Bank Blackwater
	531022111, -- main door
	2117902999, -- inner door
	2817192481, -- manager door
	1462330364, -- vault door

	-- Bank of Armadillo
	3101287960, -- main door
	3550475905, -- inner door
	1329318347, -- inner door
	1366165179, -- back door
}
