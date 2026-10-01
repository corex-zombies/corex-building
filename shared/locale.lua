Config.Locale = tostring(Config.Locale or 'en'):lower()
local selected = assert(BuildingLocales[Config.Locale], 'Unsupported building locale; use en or ar')
Config.Labels, Config.Text = selected.labels, selected.text
for name,tier in pairs(Config.Tiers) do tier.label = selected.tiers[name] or name end
