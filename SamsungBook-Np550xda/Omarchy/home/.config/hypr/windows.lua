-- Regras pessoais de janela ficam aqui.

-- Sober (Roblox): não travar a tela nem deixar transparente em fullscreen.
o.window("org.vinegarhq.Sober", { idle_inhibit = "fullscreen" })
o.window("org.vinegarhq.Sober.*", { tag = "-default-opacity", opacity = "1 1" })
