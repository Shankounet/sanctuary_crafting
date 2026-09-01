--[[
    config/community_projects.lua — import Shared.CommunityProjects
]]

Config.CommunityProjects = {
    {
        id = 'community_project_accessoires',
        label = 'Table d\'accessoires d\'armes',
        description = 'Compléter le Projet Communautaires pour pouvoir débloquer l\'acces a la table d\'accessoires d\'armes',
        img = 'https://i.postimg.cc/Pf15WcT0/accessoires.png',
        order = 0,
        items = { { item = 'plastic', count = 500 }, { item = 'aluminum', count = 750 }, { item = 'glass', count = 500 }, { item = 'electronicscrap', count = 750 }, { item = 'scrapmetal', count = 2000 } },
    },
    {
        id = 'community_project_pontcayo',
        label = 'Réparation du pont de Cayo',
        description = 'Le sanctuaire proppose de réparer le pont menant à Cayo, il demande juste la participation de tous les survivants afin d\'obtenir les ressources nécessaires.Le Sanctuaire vous remercie par avance !',
        img = 'https://r2.fivemanage.com/2DPDfRtzJlbdmO5x7Xb7F/Screenshot_3.jpg',
        order = 1,
        items = { { item = 'cloth_part', count = 5000 }, { item = 'stone', count = 3000 }, { item = 'scrapmetal', count = 12000 }, { item = 'aluminum', count = 2500 } },
    },
}
