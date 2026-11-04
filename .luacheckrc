std = "lua54"
read_globals = { "hs", "spoon" }
max_line_length = 120

-- The tests replace the hs and spoon globals and fake methods that ignore self.
files["tests"] = { globals = { "hs", "spoon" }, self = false }
