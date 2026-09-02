--[[
    Config.Specializations — identités de métier (≠ ml_skills)
    Une spec principale max. Survie = tout le monde. Stations non mappées = tout le monde.
    Ne pas inventer une 5e spec. Lire Config, ne pas hardcoder les ids en logique métier.
]]

Config = Config or {}

Config.Specializations = {
    Enabled = true,
    SurvivalId = 'survie',
    SurvivalLabel = 'Survie',
    SurvivalStations = { 'survie', 'survival', 'cuisine', 'agriculture', 'scrap', 'tailleur', 'boucherie', 'decoration' },
    MaxMain = 1,
    FromJob = {
        medecin = 'medecin', ambulance = 'medecin',
        ingenieur = 'ingenieur',
        mechanic = 'mecano', mecano = 'mecano',
        armurier = 'armurier',
    },
    Main = {
        medecin = { label = 'Médecin', skillCategory = 'medecin', stations = { 'medical' } },
        ingenieur = { label = 'Ingénieur', skillCategory = 'ingenieur', stations = { 'ingenieur', 'schema', 'construction' } },
        mecano = { label = 'Mécanicien', skillCategory = 'mechanic', stations = { 'mecano', 'mechanic' } },
        armurier = { label = 'Armurier', skillCategory = 'armurier', stations = { 'armurier', 'munition', 'weapons' } },
    },
}
