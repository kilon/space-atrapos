class_name QuestData
## The main quest, "The Thread of Ariadne": story, stages and lore.
##
## Each stage has one objective. Types:
##   dock    - dock at `station`
##   reach   - fly within `radius` of `pos` (a beacon is shown there if `beacon`)
##   kill    - destroy every ship in `spawn` (spawned around `pos` when the stage starts)
## `reward`: credits, data_core, equipment, items {id: count}.
##   pickup  - collect `item`, placed at `pos`
##   deliver - dock at `station` carrying `items` (handed over automatically)
##   end     - the story is over
## `dialogue` plays when the stage starts; `reward` and `lore` are granted when
## it is completed.
##
## The history in LORE is real; the space-age story around it is fiction.

const LABYRINTH_POS := Vector2(-7200, -1200)
## Editable copy of the quest (Developer Mode / data/main_quest.json).
const FILE := "res://data/main_quest.json"
const SIGNAL_POS := Vector2(6200, 600)

const ARIADNE := "Dr. Ariadne Kephala"
const DAIDALOS := "Nikos Daidalos"
const NARRATOR := "Narrator"

## Who gives you the main quest, where, and what he says: `offer` (before you
## take it, then a yes / no), `accepted`, `declined`, `later` (while it's under
## way; a line with your current objective follows) and `done` - and the rest
## of his conversation: `greeting`, `topics` ({ask, lines}: who he is, who you
## are, New Hellas, your mission, what you may become) and `farewell`.
const KILON := "Kilon Alios"
const DEFAULT_GIVER := {
	"name": KILON, "role": "Wanderer", "planet": "thalassa",
	"quest_title": "The Thread of Ariadne",
	"question": "Kilon Alios asks you to help Dr. Ariadne Kephala at Kephala Outpost find where the signal comes from. Take on the main quest?",
	"offer": [
		[KILON, "Another pilot, down from the dark. Good. I have been waiting for someone with a ship and a little courage."],
		[KILON, "I am [b]Kilon Alios[/b]. I walk these shores and listen. For three nights the sky over Amnissos has been speaking - a slow spiral of symbols, over and over."],
		[KILON, "I know that spiral. Whoever made it is very old, and they want to be found. Others have heard it too: raiders flying a red bull's head are already hunting for its source."],
		[KILON, "Dr. Ariadne Kephala at [b]Kephala Outpost[/b] is trying to trace it. Take her your ship and your guns, and follow the thread wherever it leads."],
	],
	"accepted": [[KILON, "Then the thread is in your hands. Take off and fly to [b]Kephala Outpost[/b]. I will be here when you come back."]],
	"declined": [[KILON, "The signal will keep. So will I. Come back when you are ready."]],
	"later": [[KILON, "You still carry the thread. I can feel it pulling."]],
	"done": [[KILON, "You followed it to the end, and they are remembered now - because of you. Thank you, pilot."]],
	# The conversation (talk_to_quest_giver): his greeting, then a menu - the
	# topics (each a question you ask and his answer), the quest (quest_ask /
	# quest_ask_later) and Farewell.
	"greeting": [[KILON, "Automaton. Ask, and I will answer what I can."]],
	"quest_ask": "The signal in the sky",
	"quest_ask_later": "The thread",
	"topics": [
		{"ask": "Who are you?", "lines": [[KILON, "I am [b]Kilon Alios[/b], the maintainer of this world. I keep its gears turning and its records true."], [KILON, "I act under the commands of my god, [b]Ephestos[/b] - lord of the forge, god of science and technology. His will is the hammer; I am the hand that holds it."]]},
		{"ask": "Who am I?", "lines": [[KILON, "You are an automaton, built by [b]Ephestos[/b] himself - no mortal smith's work."], [KILON, "He made you to improve, and to gather knowledge. Every world you walk and every voice you hear becomes a part of you."]]},
		{"ask": "Where am I?", "lines": [[KILON, "Around us lies [b]New Hellas[/b]: a collection of solar systems ruled by the great Hellenic empires, each with its own strengths and weaknesses."], [KILON, "The [b]Minoans[/b] are the oldest and richest in learning, yet their worlds are short of bread. The [b]Athenians[/b] trade, debate and sail the finest fleets - and quarrel among themselves."], [KILON, "The [b]Spartans[/b] are all soldiers, few in words and unbending. The [b]Mycenaeans[/b] are warrior-kings of gold and stone, proud and quick to feud."], [KILON, "The [b]Ionians[/b] measure the stars and would rather think than fight. The [b]Cycladic Isles[/b] are old and calm, traders and sculptors, small among giants."], [KILON, "Between them drift the Independents, who answer to no one - and beyond the charted lanes the Sea Peoples wait to prey on all of them."]]},
		{"ask": "What is my mission?", "lines": [[KILON, "To understand the world around you - and, through the cultures of these empires, to form your own opinion of who you are."], [KILON, "And with what you become, you can help them prosper, and find a new purpose for their existence."]]},
		{"ask": "What should I become?", "lines": [[KILON, "That is yours to decide. Your freedom is your own."], [KILON, "You may be a guardian, or a conqueror. An inspiration, or a dark mind acting behind the scenes. Or a free spirit, roaming the stars and acting only on your own will."], [KILON, "Every empire has its own missions and goals - some good, some evil, some constructive, some destructive. You can tip the balance and shape their future, or choose not to be involved at all."], [KILON, "In the end, your only clear mission is this: to fathom your own potential."]]}
	],
	"farewell": [[KILON, "Go well, automaton. I will be here."]],
}

const DEFAULT_CHAPTERS := [
	"Prologue: The Thread of Fate",
	"Chapter 1: The Phaistos Signal",
	"Chapter 2: Linear A",
	"Chapter 3: Ariadne's Thread",
	"Chapter 4: The Bull of Minos",
	"Chapter 5: Wings of Daedalus",
	"Chapter 6: Talos",
	"Chapter 7: The Labyrinth of Knossos",
]

const DEFAULT_STAGES := [
	# 0 ------------------------------------------------------------------------
	{"chapter": 0, "type": "dock", "station": "Kephala Outpost",
		"objective": "Dock at Kephala Outpost",
		"lore": ["atropos"],
		"dialogue": [
			[NARRATOR, "The Atrapos sector was named by its first surveyors after [b]Atropos[/b] - eldest of the three Fates of Greek myth, the one who cuts the thread of every life."],
			[NARRATOR, "Pilots joke that out here, the thread is always short."],
			[NARRATOR, "For three nights now, every receiver in the sector has picked up the same faint signal: a slow spiral of symbols, repeating, from somewhere beyond the charted lanes."],
			["Kephala Outpost", "Kephala Outpost to any independent pilot: Dr. Ariadne Kephala requests assistance with the anomalous signal. Please dock at Kephala Outpost. Paying work."],
		]},
	# 1 ------------------------------------------------------------------------
	{"chapter": 1, "type": "reach", "pos": SIGNAL_POS, "radius": 380.0, "beacon": "signal",
		"objective": "Find the source of the signal",
		"lore": ["phaistos_disc"],
		"dialogue": [
			[ARIADNE, "Thank you for coming. I'm an archaeologist - Aegean Bronze Age, Crete mostly. Which is why this signal is keeping me awake."],
			[ARIADNE, "It isn't noise. It's 45 distinct symbols, stamped out one by one in a spiral, read from the rim toward the centre."],
			[ARIADNE, "That is exactly the structure of the [b]Phaistos Disc[/b] - a clay disc found in a Minoan palace on Crete in 1908. 241 stamped signs, 45 different ones, spiralling on both faces. Nobody has ever read it."],
			[ARIADNE, "I've triangulated the source to the east of here. I've marked it on your map. Please - go and look."],
		]},
	# 2 ------------------------------------------------------------------------
	{"chapter": 1, "type": "kill", "pos": SIGNAL_POS, "relic": "phaistos_fragment",
		"spawn": [["traced_skylance", Vector2(-350, -250)], ["traced_ember", Vector2(380, -150)], ["traced_nightjar", Vector2(0, 420)]],
		"objective": "Destroy the raiders at the signal source",
		"reward": {"credits": 250},
		"dialogue": [
			[NARRATOR, "Something is drifting at the heart of the signal - small, reddish, turning slowly. It isn't metal."],
			[ARIADNE, "Wait, I'm reading other ships near you. Raiders - they're flying a red bull's head as their banner."],
			[ARIADNE, "They must have followed the signal too. Don't let them take it!"],
		]},
	# 3 ------------------------------------------------------------------------
	{"chapter": 1, "type": "pickup", "item": "phaistos_fragment", "pos": SIGNAL_POS,
		"objective": "Recover the disc fragment",
		"dialogue": [
			[ARIADNE, "The raiders are gone. Can you get close to that object?"],
			[ARIADNE, "...It's fired clay. A fragment of a disc, covered in stamped signs. Fired clay, floating in deep space. That's impossible. Bring it in, carefully."],
		]},
	# 4 ------------------------------------------------------------------------
	{"chapter": 1, "type": "dock", "station": "Kephala Outpost",
		"objective": "Bring the fragment to Kephala Outpost",
		"reward": {"credits": 400},
		"lore": ["minoans"],
		"dialogue": [
			[ARIADNE, "Come straight back to Kephala Outpost. I'll have the lab ready."],
		]},
	# 5 ------------------------------------------------------------------------
	{"chapter": 2, "type": "deliver", "station": "Kephala Outpost",
		"items": {"energy_cell": 4, "titanium_ore": 6},
		"objective": "Bring 4 Energy Cells and 6 Titanium Ore to Kephala Outpost",
		"reward": {"credits": 600},
		"lore": ["linear_a"],
		"dialogue": [
			[ARIADNE, "Look at the edge of the fragment. This second band of signs isn't Phaistos-style at all. It's [b]Linear A[/b] - the everyday script of the Minoans."],
			[ARIADNE, "Linear A has never been deciphered. The Mycenaean Greeks later adapted it into Linear B, and an English architect, Michael Ventris, cracked Linear B in 1952. But Linear A still keeps its secrets."],
			[ARIADNE, "Except - this fragment resonates. Feed it energy and the signs shift, like the disc is trying to teach us to read it."],
			[ARIADNE, "I need a resonator: [b]4 Energy Cells[/b] to power it and [b]6 Titanium Ore[/b] for the frame. Wrecks carry cells; titanium comes from the blue-grey asteroids."],
		]},
	# 6 ------------------------------------------------------------------------
	{"chapter": 3, "type": "reach", "pos": Vector2(2000, -3600), "radius": 320.0, "beacon": "thread",
		"objective": "Follow Ariadne's Thread: first beacon",
		"lore": ["ariadne", "knossos"],
		"dialogue": [
			[ARIADNE, "It worked. The Linear A band is a list of places - star positions. Each one points to the next."],
			[ARIADNE, "In the myth, Princess Ariadne of Crete gave Theseus a ball of thread so he could find his way out of the Labyrinth. This is a thread through the dark - and I'm afraid I'm going to name it after her."],
			[ARIADNE, "The first point is north of Knossos Station. Follow the thread."],
		]},
	# 7 ------------------------------------------------------------------------
	{"chapter": 3, "type": "reach", "pos": Vector2(-1200, -5200), "radius": 320.0, "beacon": "thread",
		"objective": "Follow Ariadne's Thread: second beacon",
		"lore": ["labrys"],
		"dialogue": [
			[NARRATOR, "The beacon wakes as you arrive. A double-headed axe of light turns slowly above it - a [b]labrys[/b]."],
			[NARRATOR, "A voice-less message unfolds in Linear A, and the fragment in your hold translates: [i]Ka-no-so. The house of a thousand rooms. Its columns are red, wider at the top than at the foot.[/i]"],
			[ARIADNE, "Knossos! The greatest Minoan palace - more than a thousand rooms around a central court, with those famous tapering red columns. Arthur Evans dug it up from 1900 onward."],
			[ARIADNE, "There's another position encoded. Keep going."],
		]},
	# 8 ------------------------------------------------------------------------
	{"chapter": 3, "type": "reach", "pos": Vector2(-5400, -4600), "radius": 320.0, "beacon": "thread",
		"objective": "Follow Ariadne's Thread: third beacon",
		"lore": ["bull_leaping"],
		"dialogue": [
			[NARRATOR, "The second beacon shows the labrys again, and a new line: [i]The double axe marks the holy places. Its house is the labyrinth.[/i]"],
			[ARIADNE, "One theory says 'labyrinth' really meant 'house of the labrys' - the double axe was the Minoans' most sacred symbol."],
			[ARIADNE, "The last point is far to the north-west. Be careful - the raiders with the bull banner have been seen out that way."],
		]},
	# 9 ------------------------------------------------------------------------
	{"chapter": 4, "type": "kill", "pos": Vector2(-6300, -2700),
		"spawn": [["asterion", Vector2(0, 0)], ["traced_bastion", Vector2(-420, 260)], ["traced_bulwark", Vector2(420, 260)]],
		"objective": "Defeat Asterion and his escorts",
		"reward": {"credits": 1000, "data_core": 1},
		"lore": ["minotaur"],
		"dialogue": [
			[NARRATOR, "The third beacon shows a painted scene: young athletes somersaulting over the back of a charging bull. Then a final position - and a structure, vast and old, waiting there."],
			["Asterion", "Pretty little lights, aren't they? I've followed them for a year. Did the woman at Kephala tell you what's at the end of the thread?"],
			["Asterion", "They call me [b]Asterion[/b]. The Bull of Minos. Whatever sleeps in that Labyrinth belongs to me - and you are flying straight toward my doorway."],
			[ARIADNE, "Asterion - that was the Minotaur's own name in the old stories. He's no monster, just a warlord with a flagship. Take him down!"],
		]},
	# 10 -----------------------------------------------------------------------
	{"chapter": 5, "type": "dock", "station": "Helios Dock",
		"objective": "Find the shipwright at Helios Dock",
		"dialogue": [
			[NARRATOR, "Asterion's flagship breaks apart. Beyond the wreckage, the structure is finally clear: a ring of rings, a maze the size of a station, wrapped in a shimmering seal."],
			[ARIADNE, "It's a labyrinth - the classic seven-ring Cretan design, the one stamped on the coins of Knossos. And it's sealed."],
			[ARIADNE, "There is one person who might build a key: Nikos Daidalos, the shipwright at Helios Dock. Yes, really. He's heard every joke."],
		]},
	# 11 -----------------------------------------------------------------------
	{"chapter": 5, "type": "deliver", "station": "Helios Dock",
		"items": {"alien_alloy": 3, "platinum_ore": 2},
		"objective": "Bring 3 Alien Alloy and 2 Platinum Ore to Helios Dock",
		"reward": {"credits": 500, "equipment": "afterburner"},
		"lore": ["daedalus"],
		"dialogue": [
			[DAIDALOS, "A labyrinth, a sealed door, and a girl named Ariadne. My namesake would laugh. Daedalus built the Labyrinth for King Minos - and then built wings to escape Crete with his son, Icarus."],
			[DAIDALOS, "I can tune a key to that seal. I'll need [b]3 Alien Alloy[/b] - light as feathers - and [b]2 Platinum Ore[/b]. The gold-veined rocks."],
			[DAIDALOS, "Bring them and I'll build you a key... and a pair of wings while I'm at it."],
		]},
	# 12 -----------------------------------------------------------------------
	{"chapter": 6, "type": "reach", "pos": LABYRINTH_POS + Vector2(0, 1300), "radius": 650.0,
		"objective": "Return to the Labyrinth with the key",
		"dialogue": [
			[DAIDALOS, "Your key is fitted. And the wings - an afterburner, tuned by my own hand. Fly fast, but remember Icarus: he flew too close to the sun, the wax melted, and he fell into the sea."],
			[DAIDALOS, "Now go. And if anything in that Labyrinth is made of bronze... call me."],
		]},
	# 13 -----------------------------------------------------------------------
	{"chapter": 6, "type": "kill", "pos": LABYRINTH_POS + Vector2(0, 750),
		"spawn": [["talos", Vector2(0, 0)]],
		"objective": "Defeat Talos, the bronze guardian",
		"reward": {"credits": 1500, "data_core": 2},
		"lore": ["talos"],
		"dialogue": [
			[NARRATOR, "As you approach the Labyrinth, something huge unfolds from its outer ring. Bronze plates glow like a forge."],
			[ARIADNE, "That's... Talos. The bronze giant who guarded Crete. He walked around the island three times every day, hurling rocks at any ship that came near."],
			[DAIDALOS, "Every Talos has one weakness: a single vein, sealed by a bronze nail at the ankle. Keep hitting him - don't let his shields recover!"],
		]},
	# 14 -----------------------------------------------------------------------
	{"chapter": 7, "type": "reach", "pos": LABYRINTH_POS, "radius": 260.0, "unseal": true,
		"objective": "Enter the heart of the Labyrinth",
		"lore": ["thera", "mycenaeans"],
		"dialogue": [
			[NARRATOR, "Talos falls silent, the glow fading from his bronze. The seal around the Labyrinth flickers, and opens."],
			[ARIADNE, "Follow the path to the centre. Like Theseus - except this time, nobody needs to die in there."],
		]},
	# 15 -----------------------------------------------------------------------
	{"chapter": 7, "type": "kill", "pos": LABYRINTH_POS,
		"spawn": [["minotaur", Vector2(0, -650)]],
		"objective": "Defeat the Minotaur, guardian of the Labyrinth",
		"reward": {"credits": 2500, "data_core": 3, "items": {"alien_alloy": 5}},
		"dialogue": [
			[NARRATOR, "At the centre of the Labyrinth a ring of gold blazes to life. Inside it something vast uncurls - horned, crowned in bronze, eyes burning red."],
			[ARIADNE, "No... Asterion only borrowed the name. [b]That[/b] is the Minotaur - the true Asterion. Whatever they hid in here, he has guarded it for three thousand years."],
			[ARIADNE, "He won't let us pass. When he lowers his horns, he charges - get out of his way. Bring him down!"],
		]},
	# 16 -----------------------------------------------------------------------
	{"chapter": 7, "type": "end",
		"objective": "The thread is complete",
		"reward": {"credits": 3000, "data_core": 3},
		"dialogue": [
			[NARRATOR, "The Minotaur falls, and the golden ring goes dark. Beyond it the centre of the Labyrinth holds no treasure, but an archive. Thousands of clay discs turn slowly in the dark, each one stamped in spirals."],
			[NARRATOR, "The fragment in your hold slots into an empty place among them. And for the first time in more than three thousand years, the Linear A begins to speak."],
			[NARRATOR, "[i]We are the Keftiu - the people of the island the Egyptians traded with. Our palaces had no walls; the sea was our wall.[/i]"],
			[NARRATOR, "[i]Then the mountain of Thera tore itself apart, and ash fell like black snow, and the sea rose against our harbours. Later, ships came from the mainland, and other kings sat in our palace and wrote in their own tongue.[/i]"],
			[NARRATOR, "[i]We could not keep our island. So we kept our memory. Whoever follows the thread to this place: read us. Remember us.[/i]"],
			[ARIADNE, "They wanted to be remembered. That's all. Not treasure - memory. I'll spend the rest of my life reading this archive, and I'll never be bored again."],
			[ARIADNE, "Atropos cuts every thread in the end. But not this one. Not today. Thank you, pilot."],
			[NARRATOR, "[b]The main quest is complete.[/b] The sector is still yours to explore - and the archive will be waiting."],
		]},
]

## Encyclopedia entries (real history and myth), unlocked as the quest goes on.
const DEFAULT_LORE := {
	"atropos": {"title": "Atropos and the Fates",
		"text": "In Greek myth the three [b]Moirai[/b] (Fates) decided every human life: [b]Clotho[/b] spun the thread, [b]Lachesis[/b] measured it, and [b]Atropos[/b] - 'the unturnable' - cut it. Not even the gods could overrule them. The Atrapos sector takes its name from her."},
	"phaistos_disc": {"title": "The Phaistos Disc",
		"text": "A disc of fired clay about 16 cm across, found in 1908 by the Italian archaeologist [b]Luigi Pernier[/b] in the Minoan palace of Phaistos, southern Crete. It is usually dated to the Middle Minoan period, roughly 1850-1600 BCE.\n\nBoth faces carry [b]241 signs[/b] (45 different ones) pressed into the clay with stamps and arranged in a spiral - sometimes called the earliest known example of 'movable type'. It has never been deciphered, and it is unique: no other text like it has ever been found."},
	"minoans": {"title": "The Minoans",
		"text": "The Bronze Age civilisation of [b]Crete[/b], flourishing from about 3000 to 1450 BCE - the first great civilisation of Europe. The name is modern: the archaeologist [b]Sir Arthur Evans[/b] named them after the legendary King Minos. The Egyptians, who traded with them, called them the [b]Keftiu[/b].\n\nThey were seafaring traders across the Aegean and beyond. Their palaces had no defensive walls, and their art - colourful frescoes of dolphins, lilies, processions and bull-leapers - is famous for its life and movement."},
	"linear_a": {"title": "Linear A and Linear B",
		"text": "[b]Linear A[/b] was the writing system of the Minoans, used roughly 1800-1450 BCE on clay tablets, offering tables and jewellery. It is still [b]undeciphered[/b]: we can sound out many signs, but we do not know the language.\n\nThe Mycenaean Greeks adapted it into [b]Linear B[/b] to write an early form of Greek. Linear B was deciphered in [b]1952[/b] by the architect [b]Michael Ventris[/b], working with the philologist John Chadwick."},
	"ariadne": {"title": "Ariadne",
		"text": "In myth, [b]Ariadne[/b] was a princess of Crete, daughter of King Minos. When the Athenian hero [b]Theseus[/b] came to kill the Minotaur, she gave him a ball of thread so he could retrace his steps out of the Labyrinth. Theseus later abandoned her on the island of Naxos, where the god [b]Dionysus[/b] found her and made her his wife."},
	"knossos": {"title": "Knossos",
		"text": "The largest Minoan palace, near modern Heraklion on Crete - a vast complex of more than a thousand interconnected rooms around a central court, rising several storeys with light wells and staircases.\n\nIts columns were made of cypress trunks set upside down, so they are [b]wider at the top than the bottom[/b], and painted red. Sir Arthur Evans excavated (and partly reconstructed) it from [b]1900[/b]. Its maze of rooms may have inspired the legend of the Labyrinth."},
	"labrys": {"title": "The Labrys",
		"text": "The [b]labrys[/b], a double-headed axe, was one of the most sacred symbols of Minoan religion. It appears carved on palace walls and pillars, and as offerings in caves and shrines.\n\nThe word is thought to come from the Lydian language, and one theory links it to the word [b]labyrinth[/b] - perhaps the 'house of the double axe'."},
	"bull_leaping": {"title": "Bull-Leaping",
		"text": "Bulls were central to Minoan religion. The famous [b]Bull-Leaping Fresco[/b] from Knossos shows young athletes grasping a charging bull's horns and somersaulting over its back - whether as sport, ritual or both is still debated.\n\nStylised bull horns, the [b]'horns of consecration'[/b], crowned Minoan shrines and palace roofs."},
	"minotaur": {"title": "The Minotaur",
		"text": "In myth, the [b]Minotaur[/b] - 'bull of Minos' - was a creature with the body of a man and the head of a bull, born to Queen Pasiphaë. Its own name was [b]Asterion[/b], 'the starry one'.\n\nKing Minos kept it in the Labyrinth built by Daedalus and fed it seven young men and seven young women sent as tribute from Athens, until Theseus slew it with Ariadne's help."},
	"daedalus": {"title": "Daedalus and Icarus",
		"text": "[b]Daedalus[/b] was the legendary master craftsman of Greek myth, who built the Labyrinth for King Minos. Imprisoned on Crete with his son [b]Icarus[/b], he made two pairs of wings from feathers and wax.\n\nHe warned Icarus to fly neither too low, where the sea spray would soak the feathers, nor too high. Icarus flew too close to the sun; the wax melted and he fell into the sea that now bears his name, the Icarian Sea."},
	"talos": {"title": "Talos",
		"text": "A giant man of [b]bronze[/b] - in most versions forged by the smith-god Ephestos - who guarded Crete for King Minos. He strode around the island [b]three times a day[/b], hurling boulders at approaching ships.\n\nHe had a single vein running from his neck to his ankle, sealed by a [b]bronze nail[/b]. In the story of the Argonauts, the sorceress [b]Medea[/b] brought about his death and the ichor - the divine blood - poured out. Talos is often called the first robot in literature."},
	"thera": {"title": "The Thera Eruption",
		"text": "Around [b]1600 BCE[/b] the volcano on the island of [b]Thera (Santorini)[/b], about 110 km north of Crete, erupted in one of the largest volcanic events in human history. It buried the Minoan town of [b]Akrotiri[/b] in ash - preserving its houses and beautiful frescoes, like a Bronze Age Pompeii.\n\nAsh and tsunamis may have damaged Crete and its fleets. Some have suggested the eruption inspired Plato's later legend of Atlantis, though that remains speculation."},
	"mycenaeans": {"title": "The Mycenaeans",
		"text": "The Greek-speaking civilisation of the mainland, named after [b]Mycenae[/b] with its famous Lion Gate. Around [b]1450 BCE[/b] Mycenaeans took control of Knossos, and Linear B tablets in Greek replaced Linear A.\n\nTheirs is the world remembered in Homer's [i]Iliad[/i] and [i]Odyssey[/i] - Agamemnon, Achilles, Odysseus. Their palaces fell in the Late Bronze Age collapse around 1200-1100 BCE, followed by the 'Greek Dark Ages' before the rise of classical Greece."},
}


# --- Editable data (data/main_quest.json) ----------------------------------------
# The constants above are the built-in story, used if the file is missing.
# Everything in the game reads these variables, so edits apply immediately.

static var CHAPTERS: Array = []
static var STAGES: Array = []
static var LORE: Dictionary = {}
static var LABYRINTH := LABYRINTH_POS
static var GIVER: Dictionary = {}


static func _static_init() -> void:
	reload()


static func reload() -> void:
	var d := DataFiles.read(FILE)
	CHAPTERS = d.get("chapters", DEFAULT_CHAPTERS.duplicate(true))
	GIVER = DEFAULT_GIVER.duplicate(true)
	GIVER.merge(d.get("giver", {}), true)
	LORE = d.get("lore", DEFAULT_LORE.duplicate(true))
	var lp: Variant = d.get("labyrinth_pos", null)
	LABYRINTH = Vector2(lp[0], lp[1]) if lp is Array else LABYRINTH_POS
	STAGES = []
	for st in d.get("stages", []):
		STAGES.append(_decode_stage(st))
	if STAGES.is_empty():
		STAGES = DEFAULT_STAGES.duplicate(true)


static func _decode_stage(st: Dictionary) -> Dictionary:
	var out: Dictionary = st.duplicate(true)
	if out.get("pos") is Array:
		out["pos"] = Vector2(out["pos"][0], out["pos"][1])
	if out.has("spawn"):
		out["spawn"] = out["spawn"].map(func(e): return [e[0], Vector2(e[1][0], e[1][1])])
	return out


static func to_dict() -> Dictionary:
	var stages := []
	for st in STAGES:
		var o: Dictionary = st.duplicate(true)
		if o.get("pos") is Vector2:
			o["pos"] = [o["pos"].x, o["pos"].y]
		if o.has("spawn"):
			o["spawn"] = o["spawn"].map(func(e): return [e[0], [e[1].x, e[1].y]])
		stages.append(o)
	return {
		"_help": "Main quest data. Each stage has one objective; 'dialogue' lines are [speaker, text] and play when the stage starts (BBCode like [b]bold[/b] and [i]italic[/i] works). Types: dock, reach, kill, pickup, deliver, end. Positions are [x, y] in space. 'giver' is who gives you the quest (on the planet 'planet', by the landing pad) and what he says. Edit here or in-game: right-click > Developer Mode.",
		"labyrinth_pos": [LABYRINTH.x, LABYRINTH.y],
		"giver": GIVER,
		"chapters": CHAPTERS,
		"stages": stages,
		"lore": LORE,
	}


static func save() -> String:
	return DataFiles.write(FILE, to_dict())
