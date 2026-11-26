#!/usr/bin/env python3
"""The empires' main quests: one story per great empire (the Minoans have
theirs, The Thread of Ariadne), written as Scenarios rules into
data/scenarios.json (ids "empire_<empire>", replaced on every run) and their
encyclopedia entries into data/main_quest.json's "lore" (ids "<empire>_...").

Each story is told the way the old poets told theirs - the Muse invoked,
gods who answer, oracles that speak in riddles, guest-friendship, offerings,
pride and its punishment - but set among the stars: ships, stations, gates.

A quest is a list of steps; each step is one of
  dock     dock at a station                       (talk, rewards)
  reach    come within reach of a place            (a beacon marks it)
  kill     destroy every ship of a group           (spawned at a place; a
           monster or warlord too; they wait in their system if you leave)
  deliver  dock at a station with goods            (taken when you arrive)
  race     reach a station's place before a timer runs out (a bonus if in time)
with its objective, the dialogue as it begins ("say") and as it ends
("done"), and rewards. The quest begins when you dock at the empire's
capital ("start"). Each scenario also carries a "walkthrough" (the events
that complete each step): tests/test_empire_quests.gd plays every quest
through with it.

    python3 tools/empire_quests.py        (then the game reads the files)
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCEN = os.path.join(ROOT, "data", "scenarios.json")
QUEST = os.path.join(ROOT, "data", "main_quest.json")

# The teller of the empires' stories: Kilon Alios, the maintainer of this
# world - he narrates, as a singer would, over the ship's radio.
N = "Kilon Alios"
K = "Kilon Alios"


def lines(*pairs):
    return [[s, t] for s, t in pairs]


# --- The stories ------------------------------------------------------------------

ATHENS = {
    "id": "empire_athens", "empire": "athens", "title": "The Olive and the Owl",
    "description": "The Athenian League's story: Athena's sacred olive withers with salt in its roots. An oracle, an offering to the Earth-shaker, a battle in the narrows and a runner's race.",
    "start": "Athenai Stoa",
    "prologue": lines(
        (N, "Sing, Muse, of the pilot who came to the city of grey-eyed Athena, when her olive withered and the sea rose against her people."),
        (N, "Long ago, men say, two gods strove for the land: Poseidon struck the rock with his trident and a salt spring leapt out; Athena planted an olive. The people chose the olive, and the city took her name."),
        ("Archon Kallias", "Welcome, stranger. Sit, eat, and then tell me your name - so the custom of our fathers commands, and so I keep it."),
        ("Archon Kallias", "Hear our grief. The olive in the garden-ring of the Akropolis, grown from the seed of the goddess's own tree, is withering. Salt is in its roots, and no engineer can say how it came there."),
        ("Archon Kallias", "When the wise do not know, the wise ask. Go to the silver mines of Laurion in the Marathon system. The priestess Diotima keeps the bronze owl there; it speaks with the voice of the goddess."),
    ),
    "steps": [
        {"t": "reach", "system": "erebos", "place": "planet:Laurion", "objective": "Seek the bronze owl at the mines of Laurion (Marathon system)",
         "done": lines(
             ("Diotima", "You come as the goddess said you would - unasked, and in a hurry. Sit. The owl does not speak to the hurried."),
             ("The Bronze Owl", "The sea's lord was robbed and has not forgotten. Where the cape of Sounion faces the dawn, thieves drank from his altar. Find them, and the salt will leave the root."),
             ("Diotima", "Sounion lies in the system of Athenai itself. The Sea Peoples have a den beyond our gates; it was they, surely."),
         ), "reward": {"credits": 300}},
        {"t": "kill", "system": "nyx", "place": "planet:Sounion", "ships": [["traced_pirate_reaver", 2], ["traced_pirate_scythe", 2]],
         "objective": "Destroy the thieves at the cape of Sounion (Athenai system)",
         "say": lines((N, "At Sounion the raiders sat round their fires like wolves round a felled stag, and the bronze trident of Poseidon lay among them, black with soot.")),
         "done": lines(
             (N, "So the thieves fell, and the trident of the Earth-shaker lay in the pilot's hold - heavy as a guilty conscience."),
             ("Archon Kallias", "You have the god's trident? Then do not keep it an hour longer than you must. Gods are not asked twice. Bring gifts with it to the harbour-shrine at Piraeus: oil, wine and bread, as our fathers did."),
         ), "reward": {"credits": 500, "reputation": 5}},
        {"t": "deliver", "station": "Piraeus Emporion", "items": {"food": 10, "luxury_goods": 4},
         "objective": "Bring 10 Food and 4 Luxury Goods to the shrine at Piraeus Emporion (Piraeus system)",
         "done": lines(
             (N, "They poured the wine on the deck of the harbour-shrine and burned the bread, and the smoke went up to the dark between the stars."),
             ("Priest of Poseidon", "The Earth-shaker has his trident and his gifts. Now set the trident back where it was taken, on the cape of Sounion, and say his name as you do it."),
         ), "reward": {"credits": 400}},
        {"t": "reach", "system": "nyx", "place": "planet:Sounion", "objective": "Return the trident to the cape of Sounion (Athenai system)",
         "say": lines((N, "Then the pilot turned the ship back towards Sounion, carrying the god's own weapon through the god's own sea.")),
         "done": lines(
             (N, "The trident was set in its place, and the pilot said the god's name. Far off, the gates of Athenai flickered once, as if a wave had passed through them, and were still."),
             ("Archon Kallias", "The salt is leaving the roots! But listen - the Sea Peoples have heard who robbed them of their prize. Their ships gather beyond Piraeus to burn our harbour."),
         ), "reward": {"credits": 300, "data_core": 1}},
        {"t": "dock", "station": "Piraeus Emporion", "objective": "Join Navarch Themistios at Piraeus Emporion (Piraeus system)",
         "done": lines(
             ("Navarch Themistios", "They are many and we are few. So we will not meet them in open space. We will meet them in the narrows before the gate to Ugarit, where their numbers are a burden and not a strength."),
             ("Navarch Themistios", "An oracle once told our fathers to trust in wooden walls. Our walls are hulls now. Yours is one of them."),
         ), "reward": {"credits": 200}},
        {"t": "kill", "system": "hekate", "place": "gate:tartaros", "ships": [["traced_pirate_banner", 3], ["traced_pirate_twinaxe", 2]],
         "objective": "Hold the narrows at the gate to Ugarit (Piraeus system)",
         "say": lines((N, "As starlings wheel over a field before rain, so the raiders came through the gate, wheeling and crying on their radios.")),
         "done": lines(("Navarch Themistios", "Their van is broken. But see - their great ships come behind, and their chief with them. Do not let them pass.")),
         "reward": {"credits": 500}},
        {"t": "kill", "system": "hekate", "place": "gate:tartaros", "ships": [["traced_pirate_skullsun", 1], ["traced_pirate_corsair", 2]],
         "objective": "Destroy the raiders' chief and his gunships in the narrows (Piraeus system)",
         "say": lines(("Raider chief", "Owl-folk! I will hang your ships from my mast like a fisher hangs his catch!")),
         "done": lines(
             (N, "So the chief fell in the narrows, and the sea of stars was strewn with wrecks as a beach is strewn with weed after a storm."),
             ("Navarch Themistios", "Victory! Now the city must hear it before rumour reaches it first - rumour is quicker than any ship. Run, pilot, to the Stoa at Athenai, and do not stop."),
         ), "reward": {"credits": 600, "reputation": 8}},
        {"t": "race", "station": "Athenai Stoa", "seconds": 240, "objective": "Run the news to Athenai Stoa before the hour turns (Athenai system)",
         "say": lines((N, "Once a runner ran from Marathon to the city with news of victory, spoke one word, and died. The pilot flew, and hoped for a kinder ending.")),
         "in_time": lines(("Archon Kallias", "Rejoice - we have won! You came faster than the rumour. The city will remember it.")),
         "late": lines(("Archon Kallias", "Rumour came before you, pilot, but it told the truth this once. No matter - you are here, and alive.")),
         "bonus": {"credits": 500},
         "done": lines(
             (N, "That day the people walked in procession round the Akropolis-ring, as at the great festival, and carried a new robe to the goddess."),
             ("Archon Kallias", "And look: the olive puts out new leaves. Grey-eyed Athena has seen it all. Take this, and take the city's thanks - you are a guest-friend of Athens, now and always."),
         ), "reward": {"credits": 1500, "data_core": 2, "reputation": 15}},
    ],
    "lore": {
        "athens_contest": {"title": "Athena and Poseidon", "text": "Two gods wanted Attica. [b]Poseidon[/b] struck the rock of the Akropolis with his trident and a spring of salt water leapt out; [b]Athena[/b] planted the first olive tree. The people judged the olive the better gift - food, oil and light - and the city became [b]Athens[/b]. Poseidon, angry, flooded the plain. Her sacred olive grew on the Akropolis ever after; when the Persians burned it, men said it put out a new shoot the very next day."},
        "athens_salamis": {"title": "The Wooden Walls", "text": "When the Persians came, the oracle at Delphi told the Athenians to trust in their [b]wooden walls[/b]. [b]Themistokles[/b] said the walls were ships. He drew the Persian fleet into the narrow strait of [b]Salamis[/b] (480 BC), where its numbers were useless, and won. A runner's famous run from [b]Marathon[/b] to Athens, ten years before, is told by later writers: he gave the news of victory and died."},
    },
}

SPARTA = {
    "id": "empire_sparta", "empire": "sparta", "title": "With Your Shield or On It",
    "description": "The Spartan Hegemony's story: a trial of the agoge, an oracle against greed, the pass of Thermopylai held against a traitor's raiders, the Twin Stars relit and Cerberus driven back at Tainaron.",
    "start": "Sparta Barracks",
    "prologue": lines(
        (N, "Sing, Muse, of Lakedaimon, the hollow land, whose people spend few words and many years of training - and of the stranger who stood among them."),
        ("Ephor Chilonis", "You. Pilot. We have a task. We do not give tasks to men we have not tested."),
        ("Ephor Chilonis", "Raiders prowl the gate to Pylos. Three of them. Go alone. Come back."),
        (N, "When a king of Macedon wrote to them, 'If I enter your land I will destroy you,' the Spartans answered with one word: 'If.'"),
    ),
    "steps": [
        {"t": "kill", "system": "kyros", "place": "gate:pylos", "ships": [["traced_pirate_reaver", 2], ["traced_pirate_bonescythe", 1]],
         "objective": "Destroy the three raiders at the gate to Pylos (Sparta system) - alone",
         "done": lines(
             ("Ephor Chilonis", "Good."),
             ("Ephor Chilonis", "Now the real task. Go to the shrine at Amyklai. The priest has an answer from Delphi. We do not like it."),
         ), "reward": {"credits": 300, "reputation": 3}},
        {"t": "reach", "system": "kyros", "place": "planet:Amyklai", "objective": "Hear the oracle at the shrine of Amyklai (Sparta system)",
         "done": lines(
             ("Priest of Apollo", "Far-shooting Apollo gave this answer to our kings long ago, and gives it again: 'Love of money, and nothing else, will destroy Sparta.'"),
             ("Priest of Apollo", "Now hear what the god did not say, but we know. Leotychidas, once our polemarch, was sent into exile for taking a bribe. He has sold the codes of the Thermopylai gate to the Sea Peoples for a sleeve full of gold."),
             ("Priest of Apollo", "The garrison at Thermopylai Citadel must hold the pass. They are few. They are hungry. Bring them what they need."),
         ), "reward": {"credits": 200}},
        {"t": "deliver", "station": "Thermopylai Citadel", "items": {"weapons": 6, "food": 10},
         "objective": "Bring 6 Weapons and 10 Food to Thermopylai Citadel (Thermopylai system)",
         "done": lines(
             ("Polemarch Dienekes", "Bread and spears. Good. Now we can fight."),
             ("Polemarch Dienekes", "A merchant told me their ships will be so many that their guns will hide the stars. Then we shall fight in the shade. Take your place at the gate to Lukka."),
         ), "reward": {"credits": 400}},
        {"t": "kill", "system": "thera", "place": "gate:skylla", "ships": [["traced_pirate_reaver", 3], ["traced_pirate_scythe", 2]],
         "objective": "Hold the pass at the gate to Lukka (Thermopylai system)",
         "say": lines((N, "They came through the narrow gate as a river comes through a gorge, and the Spartans stood in it like rocks.")),
         "done": lines(("Polemarch Dienekes", "First wave broken. They will send more. They always do.")),
         "reward": {"credits": 400}},
        {"t": "kill", "system": "thera", "place": "gate:skylla", "ships": [["traced_pirate_corsair", 2], ["traced_pirate_ribcage", 1], ["traced_pirate_maw", 2]],
         "objective": "Hold the pass against the second wave (Thermopylai system)",
         "done": lines(("Polemarch Dienekes", "There. The traitor's ship. He comes himself, to see what his gold has bought.")),
         "reward": {"credits": 500}},
        {"t": "kill", "system": "thera", "place": "gate:skylla", "ships": [["traced_pirate_galleon", 1], ["traced_pirate_skullbarge", 2]],
         "objective": "Destroy the traitor Leotychidas and his escort (Thermopylai system)",
         "say": lines(("Leotychidas", "Spartans! I offer you what I was offered - gold, and your lives. Stand aside.")),
         "done": lines(
             (N, "The gold in his sleeve did not save him. It never does; that was the meaning of the god's answer."),
             ("Polemarch Dienekes", "The pass holds. Now the Twin Stars. Kastor and Polydeukes, sons of Zeus, guard every sailor - their beacons at the Kastor Phalanx went dark when the raiders came. Relight them."),
         ), "reward": {"credits": 800, "reputation": 8}},
        {"t": "reach", "system": "g10_mantineia", "place": "station:Kastor Phalanx", "objective": "Relight the beacons of the Twin Stars at Kastor Phalanx (Mantineia system)",
         "done": lines(
             (N, "When the Twin Stars burn on a ship's mast, sailors say, the storm is over. The pilot set them burning again, and every ship in the lanes saw them."),
             ("Ephor Chilonis", "Bad news. At Tainaron, where the road to Hades opens, the three-headed hound has broken out. Herakles, father of our kings, dragged it up from below once. Now it is your turn."),
         ), "reward": {"credits": 400, "data_core": 1}},
        {"t": "kill", "system": "g3_tegea", "place": "planet:Tainaron", "ships": [["cerberus", 1]],
         "objective": "Drive Cerberus back into the dark at Tainaron (Tegea system)",
         "say": lines((N, "Three heads it had, and a mane of snakes, and its bark shook the hulls of ships as the bark of a dog shakes a sleeping house.")),
         "done": lines((N, "So the hound of Hades went back down the road it came, and the gate of Tainaron was shut."),),
         "reward": {"credits": 1200, "data_core": 1}},
        {"t": "dock", "station": "Sparta Barracks", "objective": "Return to Sparta Barracks (Sparta system)",
         "done": lines(
             ("Ephor Chilonis", "A Spartan mother tells her son, as she hands him his shield: 'With it, or on it.' You came back with yours."),
             ("Ephor Chilonis", "Take this. Few strangers are called friends of Lakedaimon. You are."),
         ), "reward": {"credits": 1500, "data_core": 2, "reputation": 15}},
    ],
    "lore": {
        "sparta_oracle": {"title": "Love of Money", "text": "The Spartans said the Delphic oracle had warned them: '[b]Love of money, and nothing else, will destroy Sparta[/b].' Their lawgiver [b]Lykourgos[/b] had made their coins of iron, too heavy to hoard. Yet more than one Spartan king, among them [b]Leotychidas[/b], was exiled for taking bribes."},
        "sparta_thermopylae": {"title": "Thermopylai", "text": "In 480 BC King [b]Leonidas[/b] and three hundred Spartans, with their allies, held the narrow pass of [b]Thermopylai[/b] against the Persian army for three days, until a traitor showed the Persians a path round it. Told the Persian arrows would hide the sun, the Spartan [b]Dienekes[/b] answered: 'Good - then we shall fight in the shade.'"},
        "sparta_dioscuri": {"title": "The Twin Stars", "text": "[b]Kastor[/b] and [b]Polydeukes[/b], the Dioskouroi, twin sons of Zeus and Leda, were Sparta's own heroes. Sailors saw them in the lights that burn on masts in a storm, and prayed to them for rescue. When Kastor died, Polydeukes shared his immortality with him: they live one day among the gods and one below, turn and turn about."},
    },
}

MYCENAE = {
    "id": "empire_mycenae", "empire": "mycenae", "title": "The Mask of Gold",
    "description": "The Mycenaean Kingdoms' story: the wanax's golden mask is stolen and the Cyclopean walls crack. The Hydra wakes at Lerna, Artemis stills the fleet as at Aulis, and Cetus rises against the homecoming.",
    "start": "Mykenai Forge",
    "prologue": lines(
        (N, "Sing, Muse, of Mykenai rich in gold, of its walls that the Cyclopes built, and of the curse that runs in its kings' blood like rust in a blade."),
        ("Wanax Agapenor", "Stranger, you stand in the hall of the wanax. Drink from my cup - and then hear me, for the gods have turned their faces from my house."),
        ("Wanax Agapenor", "The golden mask of my fathers was taken from the tholos-tomb, and the next night the Lion Gate's beacon went dark, and the great walls cracked."),
        ("Wanax Agapenor", "Old Brontes, last of the Cyclops-engines, still tends the forge at Tiryns. He built these walls. Ask him what has broken them."),
    ),
    "steps": [
        {"t": "reach", "system": "naxos", "place": "planet:Tiryns", "objective": "Ask the Cyclops-engine Brontes at Tiryns (Mykenai system)",
         "done": lines(
             ("Brontes", "One eye I have, and with it I have watched three thousand years. Walls do not crack by themselves, little one. A thief opened the tomb, and the dead were angry."),
             ("Brontes", "First mend the walls. Bring iron and titanium to the forge at the Lion Gate of Tirynthia, and I will set the stones as I set them for Perseus."),
         ), "reward": {"credits": 300}},
        {"t": "deliver", "station": "Tirynthia Lion Gate", "items": {"iron_ore": 10, "titanium_ore": 6},
         "objective": "Bring 10 Iron Ore and 6 Titanium Ore to Tirynthia Lion Gate (Tirynthia system)",
         "done": lines(
             (N, "The forge roared like a lion in a cave, and the walls grew whole again, stone locked on stone, so close that no knife-blade could pass between them."),
             ("Brontes", "The thieves took the mask towards the den of Lukka. Their sentries watch the gate from Mykenai. Clear the road."),
         ), "reward": {"credits": 500}},
        {"t": "kill", "system": "naxos", "place": "gate:skylla", "ships": [["traced_pirate_reaver", 2], ["traced_pirate_corsair", 1], ["traced_pirate_twinaxe", 1]],
         "objective": "Destroy the raiders watching the gate to Lukka (Mykenai system)",
         "done": lines(
             ("Wanax Agapenor", "The road is open. But a worse thing stirs. In the marsh of Lerna, beside our own world, the many-headed serpent that Herakles killed has grown its heads again."),
             ("Wanax Agapenor", "Herakles cut one head and two grew in its place. Do not be proud, pilot. Be patient."),
         ), "reward": {"credits": 500, "reputation": 5}},
        {"t": "kill", "system": "naxos", "place": "planet:Lerna", "ships": [["hydra", 1]],
         "objective": "Destroy the Hydra in the marsh of Lerna (Mykenai system)",
         "say": lines((N, "Nine heads it had, and its breath was poison, and the marsh boiled where it moved.")),
         "done": lines(
             (N, "So the Hydra died a second time; and the pilot did not boast of it, remembering what happens to the proud."),
             ("Wanax Agapenor", "Now we sail to take back the mask. But the fleet cannot jump. The gates are still, as the winds were still at Aulis when Artemis was wronged."),
         ), "reward": {"credits": 1000, "data_core": 1}},
        {"t": "dock", "station": "Atreus Tholos", "objective": "Ask the seer Kalchas why the gates are still (Atreus Tholos, Mykenai system)",
         "done": lines(
             ("Kalchas", "Artemis is angry. One of the wanax's captains shot a hind in her sacred grove and boasted that not even the goddess could shoot better."),
             ("Kalchas", "Once, at Aulis, she asked for a king's daughter. But in the better telling she took a hind instead, and carried the girl away to safety. Give her gifts of healing and clean water, and she will be content."),
         ), "reward": {"credits": 200}},
        {"t": "deliver", "station": "Atreus Tholos", "items": {"medicine": 5, "water": 10},
         "objective": "Bring 5 Medicine and 10 Water to Atreus Tholos for Artemis (Mykenai system)",
         "done": lines(
             (N, "They gave the goddess her gifts, and the captain who boasted gave her his bow. And the gates woke, one after another, like hounds hearing the horn."),
             ("Wanax Agapenor", "To Pylos! The thieves wait by the gate to Ugarit with the mask. Nestor's old city will see us pass."),
         ), "reward": {"credits": 400}},
        {"t": "kill", "system": "pylos", "place": "gate:tartaros", "ships": [["traced_pirate_ironwheel", 1], ["traced_pirate_banner", 2], ["traced_pirate_scythe", 2]],
         "objective": "Destroy the thieves holding the golden mask (Pylos system)",
         "done": lines(
             (N, "The thieves fell, and the golden mask lay in the wreckage, still smiling its calm gold smile."),
             ("Wanax Agapenor", "Bring it home - but beware the sea between. Once Poseidon sent a monster, Cetus, against the land of Andromeda, until Perseus of our house killed it. My dreams say it is out again."),
         ), "reward": {"credits": 600, "reputation": 5}},
        {"t": "kill", "system": "pylos", "place": "planet:Argos", "ships": [["cetus", 1]],
         "objective": "Kill Cetus, the sea-monster, near Argos (Pylos system)",
         "say": lines((N, "It rose from the dark as a whale rises from the deep, and its jaws could have swallowed a frigate whole.")),
         "done": lines((N, "So Cetus died, and the homecoming was free."),),
         "reward": {"credits": 1200, "data_core": 1}},
        {"t": "dock", "station": "Mykenai Forge", "objective": "Bring the golden mask home to Mykenai Forge (Mykenai system)",
         "done": lines(
             ("Wanax Agapenor", "The mask is in the tomb again, and the Lion Gate burns. My fathers sleep."),
             ("Wanax Agapenor", "Know this, guest: my house has a curse on it, from the day Atreus served his brother a terrible feast. Each king pays for the pride of the one before. You have bought us a little peace. Take gold for it - but take my friendship more."),
         ), "reward": {"credits": 1500, "data_core": 2, "reputation": 15}},
    ],
    "lore": {
        "mycenae_walls": {"title": "Cyclopean Walls", "text": "The walls of [b]Mykenai[/b] and [b]Tiryns[/b] are built of stones so huge that later Greeks said only the [b]Cyclopes[/b] - one-eyed giants, smiths of Zeus's thunderbolts - could have lifted them. Mykenai's gate is crowned by two stone lions. In the shaft graves inside, [b]Schliemann[/b] found gold death-masks (1876) and wired home that he had 'gazed on the face of Agamemnon'."},
        "mycenae_atreus": {"title": "The House of Atreus", "text": "[b]Atreus[/b], king of Mykenai, killed his brother's sons and served them to him at a feast; a curse fell on his house. His son [b]Agamemnon[/b] led the Greeks to Troy, but at [b]Aulis[/b] Artemis held back the winds until he offered his daughter [b]Iphigeneia[/b]; in some tellings the goddess put a hind in her place. Agamemnon came home to be murdered by his wife - and so the curse ran on."},
        "mycenae_heroes": {"title": "Heroes of the Argolid", "text": "[b]Perseus[/b], said to have founded Mykenai, killed the Gorgon and the sea-monster [b]Cetus[/b] to save [b]Andromeda[/b]. [b]Herakles[/b], born to the royal house, served the king of Mykenai for twelve labours; the second was the [b]Hydra[/b] of Lerna, whose heads grew back two for one until his nephew burned the stumps."},
    },
}

IONIA = {
    "id": "empire_ionia", "empire": "ionia", "title": "The First Principle",
    "description": "The Ionian League's story: the sages ask what all things are made of. An eclipse is foretold, the League meets at the Panionion, Herostratos burns the temple of Artemis for fame, and Skylla rises in the dark.",
    "start": "Miletos Agora",
    "prologue": lines(
        (N, "Sing, Muse, of Ionia, where men first asked not which god made the world, but what the world is made of."),
        ("Hekataios the Chronicler", "Welcome, guest. I write down the stories of the Greeks - which are many, and, it seems to me, mostly foolish. Yours I would like to hear when it is finished."),
        ("Hekataios the Chronicler", "Thales of our city foretold an eclipse of the sun, and it came on the day he named. Now the observatories say another is coming - one that will blind the gate-beacons of the whole League for an hour."),
        ("Hekataios the Chronicler", "Worse: a raider named Herostratos boasts he will do a deed so great that men will speak his name for ever. Such men are dangerous. The League's council meets at the Panionion. Go and tell them."),
    ),
    "steps": [
        {"t": "reach", "system": "g5_assos", "place": "planet:Panionion", "objective": "Bring the warning to the League's council at the Panionion (Assos system)",
         "done": lines(
             ("Speaker of the Panionion", "Twelve cities sit in this council, and twelve cities never agree. But on this we agree: Ephesos must be guarded, and the eclipse must be measured, so that the gates can be steered by hand while it lasts."),
             ("Speaker of the Panionion", "Theano of Samos, who keeps the school of Pythagoras, is building the instrument. She needs parts. Bring them to the Sappho Observatory."),
         ), "reward": {"credits": 300}},
        {"t": "deliver", "station": "Sappho Observatory", "items": {"electronics": 4, "energy_cell": 6},
         "objective": "Bring 4 Electronics and 6 Energy Cells to Sappho Observatory (Samos system)",
         "done": lines(
             ("Theano of Samos", "Pythagoras taught that all things are number: the strings of the lyre, the rings of the planets, even justice. This instrument hears the numbers of the sky, and will tell us the second the shadow falls."),
             ("Theano of Samos", "Herostratos's scouts have been seen at Ephesos, by the strait. Drive them off before they learn too much."),
         ), "reward": {"credits": 500}},
        {"t": "kill", "system": "ephesos", "place": "gate:skylla", "ships": [["traced_pirate_bonescythe", 2], ["traced_pirate_twinaxe", 2]],
         "objective": "Drive off Herostratos's scouts at the strait of Lukka (Ephesos system)",
         "done": lines(
             ("Hekataios the Chronicler", "The scouts carried fire-charges, the kind used to burn a station. Pilot - it is the temple of Artemis he means to burn. It is the greatest wonder of the League. Hurry to the temple-ring beside Ephesos Agora."),
         ), "reward": {"credits": 400}},
        {"t": "reach", "system": "ephesos", "place": "station:Ephesos Agora", "objective": "Guard the temple-ring of Artemis beside Ephesos Agora (Ephesos system)",
         "done": lines(
             ("Priestess of Artemis", "Too late to stop him reaching us - not too late to stop him finishing. He is here. Hear him."),
             ("Herostratos", "Let them burn my body afterwards! My name will outlive their temple, their League and their gods."),
         ), "reward": {"credits": 200}},
        {"t": "kill", "system": "ephesos", "place": "station:Ephesos Agora", "ships": [["traced_pirate_skullsun", 1], ["traced_pirate_reaver", 3]],
         "objective": "Destroy Herostratos before he burns the temple of Artemis (Ephesos system)",
         "done": lines(
             (N, "So Herostratos fell, and the temple stood, though its outer ring smoked for days."),
             ("Priestess of Artemis", "The Ephesians have decreed that his name shall never be spoken or written again. That is the punishment the gods give the proud: what they wanted most, taken from them."),
             ("Hekataios the Chronicler", "And yet I have just written it down. Well - a chronicler must. Now: the eclipse. Theano's instrument is at Miletos; be at the Pythagoras Artemision before the shadow falls."),
         ), "reward": {"credits": 700, "reputation": 8}},
        {"t": "race", "station": "Pythagoras Artemision", "seconds": 300, "objective": "Reach the Pythagoras Artemision before the eclipse (Miletos system)",
         "say": lines((N, "The pilot flew towards Miletos, and behind the ship the light of the sun began, very slowly, to be eaten.")),
         "in_time": lines(("Theano of Samos", "In time! The numbers are true; the gates are steered. Thales would be proud - though he would pretend not to be.")),
         "late": lines(("Theano of Samos", "The shadow came first - but the gates held, by luck and by the gods' patience. Next time, be quicker than luck.")),
         "bonus": {"credits": 500, "data_core": 1},
         "done": lines(
             (N, "And in the hour of the eclipse, when the stars came out at noon, something rose out of the strait of Lukka - six heads on long necks, and a girdle of barking dogs."),
             ("Hekataios the Chronicler", "Skylla. Homer sang of her. Odysseus lost six men to her and could not fight her. You, at least, have guns."),
         ), "reward": {"credits": 400}},
        {"t": "kill", "system": "ephesos", "place": "gate:skylla", "ships": [["skylla", 1]],
         "objective": "Destroy Skylla at the strait of Lukka (Ephesos system)",
         "say": lines((N, "As a fisherman on a rock lets down his line and pulls up a fish, so she stooped from the dark and pulled ships from the lane.")),
         "done": lines((N, "So Skylla sank back into the strait, and the eclipse passed, and the sun came back to Ionia."),),
         "reward": {"credits": 1200, "data_core": 1}},
        {"t": "dock", "station": "Homeros Odeon", "objective": "Hear the singer at Homeros Odeon (Ephesos system)",
         "done": lines(
             ("Melesigenes the Singer", "Sit, guest. I am a singer, as my fathers were. I have made a new song - about a pilot, a burned temple that did not burn, and a monster that Odysseus could not kill."),
             ("Melesigenes the Singer", "What is everything made of? Thales said water, Anaximenes air, Herakleitos fire, Pythagoras number. I say: stories. Take the League's gold - the song is free."),
         ), "reward": {"credits": 1500, "data_core": 2, "reputation": 15}},
    ],
    "lore": {
        "ionia_arche": {"title": "The First Principle", "text": "In the Ionian cities of the 6th century BC, thinkers began to explain the world without myths. [b]Thales[/b] of Miletos said everything is made of water - and was said to have foretold the solar eclipse of 585 BC. [b]Anaximenes[/b] said air; [b]Herakleitos[/b] of Ephesos said fire, and that everything flows; [b]Pythagoras[/b] of Samos said all things are number."},
        "ionia_herostratos": {"title": "Herostratos", "text": "In 356 BC a man set fire to the great [b]temple of Artemis at Ephesos[/b], one of the Seven Wonders, so that his name would live for ever. The Ephesians executed him and forbade anyone to speak or write his name. The historian Theopompos wrote it down anyway: [b]Herostratos[/b]."},
    },
}

CYCLADES = {
    "id": "empire_cyclades", "empire": "cyclades", "title": "The Wandering Isle",
    "description": "The Cycladic Isles' story: sacred Delos breaks from its four pillars and drifts, as it did before Leto bore Apollo and Artemis there. Tithes, obsidian, marble and Ariadne's crown - and Echidna, sent by Hera.",
    "start": "Delos Circle",
    "prologue": lines(
        (N, "Sing, Muse, of the Isles that stand in a circle round holy Delos, as dancers stand round an altar."),
        (N, "Once Delos was a floating island, driven by every wind. When Leto, carrying the children of Zeus, wandered the world, no land would take her in - for they feared white-armed Hera. Only Delos dared. Then Poseidon fixed it to the sea's floor with four pillars, and there Apollo and Artemis were born."),
        ("Hierophant Anthousa", "Guest, the Circle welcomes you - though you find us frightened. The four pillar-engines that anchor Delos are failing. The station has begun to drift, as the island drifted before the god was born."),
        ("Hierophant Anthousa", "Each pillar was made with a gift from one isle: Siphnos gave gold, Melos obsidian, Paros marble, Naxos the vine. We must gather the gifts again. Begin with Siphnos - and remember what happened to the Siphnians who cheated the god."),
    ),
    "steps": [
        {"t": "deliver", "station": "Siphnos Circle", "items": {"platinum_ore": 6},
         "objective": "Bring a true tithe of 6 Platinum Ore to Siphnos Circle (Siphnos system)",
         "say": lines((N, "The Siphnians grew rich from their gold mines, and each year sent Apollo a golden egg. One year they sent gilded lead. The sea came into their mines, and they were rich no longer.")),
         "done": lines(
             ("Elder of Siphnos", "True metal, honestly weighed. Our grandfathers should have done as much. The first pillar has its gift."),
             ("Elder of Siphnos", "Melos guards the black glass, obsidian - sharper than any bronze. But raiders have been robbing its quarries. Go carefully."),
         ), "reward": {"credits": 400, "reputation": 4}},
        {"t": "kill", "system": "g6_melos", "place": "gate:keros", "ships": [["traced_pirate_reaver", 2], ["traced_pirate_scythe", 2]],
         "objective": "Drive the obsidian thieves from Melos (Melos system)",
         "done": lines(
             ("Quarry-mother of Melos", "Our black glass is safe again. Take the best of it for the second pillar. Now Paros - the marble-cutters there are waiting for you."),
         ), "reward": {"credits": 500, "data_core": 1}},
        {"t": "reach", "system": "g27_paros", "place": "planet:Saliagos", "objective": "Find the marble-cutters on Saliagos (Paros system)",
         "done": lines(
             ("Arkesilas the Sculptor", "You want marble for a pillar? Then you want white marble, the finest there is - not stone, light that has gone hard. But my cutters need metal for their saws."),
         ), "reward": {"credits": 300}},
        {"t": "deliver", "station": "Paros Circle", "items": {"titanium_ore": 8},
         "objective": "Bring 8 Titanium Ore to Paros Circle for the marble-cutters (Paros system)",
         "done": lines(
             ("Arkesilas the Sculptor", "The third pillar has its marble. One isle is left: Naxos, where Dionysos found Ariadne weeping on the shore, and crowned her with stars."),
         ), "reward": {"credits": 500}},
        {"t": "reach", "system": "g20_naxia", "place": "planet:Aplomata", "objective": "Seek the vine-crown on Aplomata (Naxia system)",
         "say": lines((N, "Theseus left Ariadne asleep on Naxos and sailed for Athens. When she woke, his ship was a speck on the sea. But the god Dionysos came with his singing train, and made her his wife.")),
         "done": lines(
             ("Maenad of Naxos", "This is her crown - the one the god set in the sky as a ring of stars when she died. A copy, but a holy one. Take it to Delos; it is the fourth gift."),
             ("Maenad of Naxos", "But be warned. The white-armed queen of the gods has not forgotten Leto. She sent the serpent after her once. She has sent another."),
         ), "reward": {"credits": 400}},
        {"t": "kill", "system": "g40_delos", "place": "station:Delos Circle", "ships": [["echidna", 1]],
         "objective": "Destroy Echidna, sent by Hera, before Delos Circle (Delos system)",
         "say": lines((N, "Half a nymph she was, with lovely cheeks and bright eyes, and half a dreadful serpent - Echidna, mother of monsters, coiling round the drifting ring.")),
         "done": lines((N, "So the serpent fell, as Python fell to Apollo's arrows; and the ring of Delos stood still on its pillars once more."),),
         "reward": {"credits": 1200, "data_core": 1}},
        {"t": "reach", "system": "g40_delos", "place": "station:Delos Circle", "objective": "Raise the four pillars at Delos Circle (Delos system)",
         "done": lines(
             ("Hierophant Anthousa", "Gold, obsidian, marble and the vine. The pillars are raised. Delos stands where Leto found her rest, and the god's light burns in the Circle."),
             ("Hierophant Anthousa", "One rite remains. On Keros, the old people broke their marble figures and laid them down, all together, in one place. We still do. Bring the offering there."),
         ), "reward": {"credits": 500, "reputation": 5}},
        {"t": "deliver", "station": "Keros Quarry", "items": {"luxury_goods": 3},
         "objective": "Bring 3 Luxury Goods to Keros Quarry for the rite of broken figures (Keros system)",
         "done": lines(
             (N, "They broke the white figures with their folded arms and their quiet faces, and laid the pieces down together, as their fathers had for a thousand years. No one now knows why. Perhaps it does not matter."),
             ("Hierophant Anthousa", "The Isles are one circle again. Take our thanks, guest - and our gold, which is honest."),
         ), "reward": {"credits": 1500, "data_core": 2, "reputation": 15}},
    ],
    "lore": {
        "cyclades_delos": {"title": "Delos", "text": "Delos, the small island at the centre of the Cyclades ('the circling isles'), was said to have floated free until [b]Leto[/b], pursued by Hera's jealousy, gave birth there to [b]Apollo[/b] and [b]Artemis[/b]; then it was fixed to the sea-bed on four pillars. It became one of the holiest places in Greece: no one was allowed to be born or to die on it."},
        "cyclades_isles": {"title": "Gold, Obsidian and Marble", "text": "[b]Siphnos[/b] grew rich on gold and silver and sent Apollo a golden egg each year, until (the story goes) it cheated him with gilded lead and the sea flooded its mines. [b]Melos[/b] traded obsidian for thousands of years before metal. [b]Paros[/b] gave the finest white marble. On [b]Keros[/b], archaeologists found thousands of marble figurines, broken on purpose and laid together - no one knows why."},
    },
}

# Second telling: what is said as each step begins, for the steps that set
# off in silence (quest id -> step index -> lines).
SCENES = {
    "empire_athens": {
        0: lines((N, "Laurion: a grey moon riddled with old shafts, where the city's silver was dug by men who never saw the sun. There the owl keeps its watch."),),
        2: lines(("Archon Kallias", "Do not haggle over the gifts, pilot. A man who bargains with a god has already lost."),),
        4: lines((N, "In Piraeus the ships lay side by side like spears in a rack, and their crews sharpened their weapons and said little."),),
    },
    "empire_sparta": {
        0: lines((N, "Spartan boys were sent out alone, with no shoes and one cloak, to live by their wits. The ephor asked the stranger for less than that - and watched closely all the same."),),
        1: lines(("Ephor Chilonis", "Amyklai. The shrine of Apollo, where Hyakinthos died. Listen to the priest. Speak little."),),
        2: lines((N, "Thermopylai: the hot gates. A narrow way between the mountains and the sea, where a few may hold back many - if they are fed, and armed, and do not run."),),
        6: lines((N, "Two stars, side by side, that sailors look for when the storm is worst. Their beacons had gone out the night the traitor's raiders came."),),
        8: lines(("Ephor Chilonis", "Come back. Report. Keep it short."),),
    },
    "empire_mycenae": {
        0: lines((N, "Tiryns of the great walls: there the Cyclops-engine still beats its anvil, slow as a heart, as it has since the days of Perseus."),),
        1: lines(("Brontes", "Iron for the bones of the wall, titanium for its sinews. Bring them, and I will make it whole."),),
        2: lines((N, "The pass to Lukka: where the raiders watch, as crows watch a field from the top of a dead tree."),),
        4: lines(("Wanax Agapenor", "Kalchas sees what was, what is and what will be. He has never told a king good news. Go and hear him anyway."),),
        5: lines(("Kalchas", "Medicine for her healing hands, water for her clean springs. Artemis loves the wild things, and those who keep them whole."),),
        6: lines((N, "Sandy Pylos, where old Nestor ruled - he who talked longest of all the Greeks at Troy, and was listened to, for he was wise."),),
        8: lines((N, "And so the pilot came home with the mask, as Agamemnon came home from Troy - but to a kinder welcome."),),
    },
    "empire_ionia": {
        0: lines((N, "The Panionion stands on the headland of Mykale, where the twelve Ionian cities met each year to sacrifice to Poseidon and to quarrel."),),
        2: lines(("Theano of Samos", "Be quick and be careful. A man who wants to be remembered will do anything to be noticed."),),
        3: lines((N, "The temple of Artemis at Ephesos had a hundred and twenty-seven columns, each the gift of a king. Its ring now shone in the dark beside the Agora like a crown laid on black cloth."),),
        4: lines(("Herostratos", "Burn, ring of Artemis! Let the whole League see the fire, and say my name!"),),
        7: lines(("Hekataios the Chronicler", "The singer at the Odeon has asked for you. Singers do not usually ask - they are usually asked. Go."),),
    },
    "empire_cyclades": {
        0: lines(("Elder of Siphnos", "A guest from the Circle! Sit; you shall have bread and figs before you have business. Then weigh your metal on our scales, and weigh it fairly."),),
        5: lines(("Hera's Voice", "Leto's children were born on that rock against my will. Let the rock drift, and let it sink."),
                 ("Hierophant Anthousa", "Do not answer her, pilot. One does not argue with the queen of the gods. One simply wins."),),
        1: lines((N, "Melos: an island of black glass, whose people cut it into knives and arrow-heads long before the first smith blew on a fire."),),
        2: lines(("Hierophant Anthousa", "Paros. Its marble is so white that sculptors say it glows from inside. Ask for Arkesilas - he will complain, then help."),),
        3: lines(("Arkesilas the Sculptor", "Bring metal. Not much - marble is patient, but my saws are not."),),
        6: lines((N, "Then the pilot brought the four gifts to Delos: gold, black glass, white marble and the vine-crown of Ariadne."),),
        7: lines((N, "Keros: a small island where nobody lives, and where, for a thousand years, the people of the Isles came to break what they had made."),),
    },
}

for _q in [ATHENS, SPARTA, MYCENAE, IONIA, CYCLADES]:
    for _i, _extra in SCENES.get(_q["id"], {}).items():
        _q["steps"][_i]["say"] = _q["steps"][_i].get("say", []) + _extra

QUESTS = [ATHENS, SPARTA, MYCENAE, IONIA, CYCLADES]


# --- Kilon Alios on every planet ------------------------------------------------
# On each world he greets you as one of the people who hold it, and tells of
# them - their history, their gods, their great deeds - and, everywhere, the
# story of New Hellas (QuestData.GIVER "empires" / "hellas"; planet_surface.gd).

KILON_EMPIRES = {
    "minoa": {"greeting": lines((K, "Welcome to the land of the Minoans, the oldest people of the sea. They were great before the others learned to sail.")),
        "topics": [
            {"ask": "Who are the Minoans?", "lines": lines(
                (K, "Long before Athens was a village, the Minoans ruled the sea from Knossos. Their ships went everywhere; their palaces had no walls, for the sea was their wall."),
                (K, "They wrote in signs no one can now read, and painted their walls with dolphins, lilies and young people leaping over bulls."))},
            {"ask": "What gods do they honour?", "lines": lines(
                (K, "A great goddess, who holds snakes in her raised hands, and the bull - Poseidon's beast. Their holy sign is the labrys, the double axe."),
                (K, "In the Labyrinth beneath Knossos lived the Minotaur, son of a queen and a bull. Daidalos built the maze; Ariadne's thread led Theseus out of it."))},
            {"ask": "What became of old Crete?", "lines": lines(
                (K, "The island of Thera burst like a cracked pot, and the sea rose against Crete. After that the mainland kings came and took the palaces."),
                (K, "But a people is not a palace. They remembered, and in New Hellas they rule again."))},
        ]},
    "athens": {"greeting": lines((K, "You stand in the land of grey-eyed Athena. Here men argue in the assembly before they take up arms - and sometimes instead of it.")),
        "topics": [
            {"ask": "Who are the Athenians?", "lines": lines(
                (K, "A people of talkers, builders, sailors and thinkers. Every citizen may speak in their assembly, and every citizen does."),
                (K, "Solon gave them laws, Kleisthenes gave them a voice, and Perikles built them the Parthenon. Then they quarrelled with Sparta, and lost much of it."))},
            {"ask": "What gods do they honour?", "lines": lines(
                (K, "Athena above all - wise in counsel and terrible in war, with her owl and her olive. Each year they carry a new robe to her in procession."),
                (K, "Poseidon they honour too, carefully, for he lost the contest for their land and has never quite forgiven it."))},
            {"ask": "What are their great deeds?", "lines": lines(
                (K, "At Marathon their hoplites ran at the Persians and broke them. At Salamis their ships, the 'wooden walls' of the oracle, broke the Persian fleet."),
                (K, "And in their theatres they invented tragedy and comedy - which may be the greater deed. Battles are forgotten; Sophokles is not."))},
        ]},
    "sparta": {"greeting": lines((K, "This is Lakedaimon. Speak briefly - they will like you better.")),
        "topics": [
            {"ask": "Who are the Spartans?", "lines": lines(
                (K, "A people who made themselves an army. At seven their boys leave home for the agoge, the training, and they live by its rules until they are old."),
                (K, "Lykourgos gave them their laws and made their money of iron, so that no one could hoard it. They grew strong, and proud, and few."))},
            {"ask": "What gods do they honour?", "lines": lines(
                (K, "Apollo of Amyklai, Artemis Orthia at whose altar boys showed they could bear pain, and Ares, whom they keep in chains in a temple so that war will never leave them."),
                (K, "And the Twin Stars - Kastor and Polydeukes, Spartan princes, sons of Zeus - who ride before their armies and save sailors in the storm."))},
            {"ask": "What are their great deeds?", "lines": lines(
                (K, "Three hundred held the pass of Thermopylai against an empire, and died there to the last man but one. Their stone says: 'Go, tell the Spartans, passer-by, that here, obedient to their laws, we lie.'"),
                (K, "Their kings claim descent from Herakles. Their women own land and speak their minds, which shocked the rest of Greece greatly."))},
        ]},
    "mycenae": {"greeting": lines((K, "Mykenai, rich in gold. Look at the walls - no man built those. Or so they say.")),
        "topics": [
            {"ask": "Who are the Mycenaeans?", "lines": lines(
                (K, "The kings of the bronze age of the mainland, who went to Troy. They lived in citadels behind walls of giant stones and were buried with masks of gold."),
                (K, "Their king was the wanax, and every jar of oil in his storerooms was counted on clay tablets."))},
            {"ask": "What gods do they honour?", "lines": lines(
                (K, "Zeus and Hera, Poseidon, Hermes, Dionysos - their tablets name them, the oldest written names of our gods."),
                (K, "And the Cyclopes, one-eyed smiths, who forged Zeus's thunderbolts and, they say, lifted the stones of these walls."))},
            {"ask": "What are their great deeds?", "lines": lines(
                (K, "Agamemnon of Mykenai led a thousand ships to Troy. Perseus, who founded this city, killed the Gorgon; Herakles, born of its royal house, did his twelve labours for its king."),
                (K, "But their house was cursed. Atreus did a terrible thing, and each king after him paid for it. Pride, and the price of pride - that is their story."))},
        ]},
    "ionia": {"greeting": lines((K, "Ionia, where men first asked questions without waiting for the gods to answer.")),
        "topics": [
            {"ask": "Who are the Ionians?", "lines": lines(
                (K, "Twelve cities on a bright coast - Miletos, Ephesos, Samos and the rest - rich with trade and full of restless minds."),
                (K, "Here Thales asked what the world is made of, Anaximander drew the first map, and Herakleitos said no one steps in the same river twice."))},
            {"ask": "What gods do they honour?", "lines": lines(
                (K, "Artemis of Ephesos, whose temple was a wonder of the world; Apollo at Didyma, whose oracle answered the Ionians; Hera on Samos, in the greatest temple of the Greeks."),
                (K, "And Poseidon at the Panionion, where the twelve cities met each year to sacrifice to him together - and to quarrel."))},
            {"ask": "What are their great deeds?", "lines": lines(
                (K, "They rose against the Persian king, and lost, and Miletos was burned. Yet the spark they lit became the war that freed Greece."),
                (K, "And Homer, the singer of Troy and of Odysseus, was an Ionian, some say from Smyrna, some from Chios. Every Greek child learned to read from his songs."))},
        ]},
    "cyclades": {"greeting": lines((K, "The Isles in their circle. The people here are old and quiet; they were carving marble when the rest of Greece was still learning to farm.")),
        "topics": [
            {"ask": "Who are the Islanders?", "lines": lines(
                (K, "Sailors and traders of the Cyclades - the circling isles, set round holy Delos. Melos had its obsidian, Paros its marble, Siphnos its gold."),
                (K, "Their oldest makers carved white figures with folded arms and faces with only a nose. No one knows their names. Their work outlived every king."))},
            {"ask": "What gods do they honour?", "lines": lines(
                (K, "Apollo and Artemis, born on Delos; Leto their mother, who found rest there. Dionysos, who found Ariadne weeping on Naxos and made her his bride."),
                (K, "No one may be born or die on Delos; the island is the god's. Even the dead were moved away."))},
            {"ask": "What are their great deeds?", "lines": lines(
                (K, "They do not boast of great deeds. They traded, they carved, they sailed. When Thera's mountain burst, they buried their town and lived on."),
                (K, "Perhaps that is their great deed: they endured, when greater peoples did not."))},
        ]},
    "pirates": {"greeting": lines((K, "A raiders' world. Keep your hand near your weapon and your purse closer.")),
        "topics": [
            {"ask": "Who are the Sea Peoples?", "lines": lines(
                (K, "In the old days ships came from no one knows where - Shardana, Lukka, Danuna, Peleset - and burned the cities of the bronze age, from Ugarit to Pylos."),
                (K, "The kingdoms fell and writing was forgotten for four hundred years. Their heirs in New Hellas raid the lanes, and the empires have not yet learned to stop them."))},
        ]},
    "independent": {"greeting": lines((K, "A free world. No empire holds it, and every empire trades here.")),
        "topics": [
            {"ask": "Who lives here?", "lines": lines(
                (K, "Those who belong to no city: traders, exiles, ship-wrights, runaways. The old Greeks called such men metics - welcome, but never quite at home."),
                (K, "Be kind to them. Zeus protects strangers, and you are a stranger too."))},
        ]},
}

KILON_HELLAS = [
    {"ask": "How did New Hellas begin?", "lines": lines(
        (K, "When the old sea grew too small for the children of Hellas, they built ships for the dark between the stars, as their fathers built ships for the wine-dark sea."),
        (K, "Each people went out together and named their new worlds after the old: Athenai, Sparta, Mykenai, Miletos, Knossos, Delos. So the old land was carried into the sky, as a man carries fire in a pot."),
        (K, "They called the whole of it New Hellas: fifty-eight suns, six great peoples, and the free ports between."))},
    {"ask": "Who built the gates?", "lines": lines(
        (K, "Ephestos, my maker, forged them at the bidding of Zeus - rings of bronze and fire at the edge of every sun, so that no people would be cut off from the others."),
        (K, "The Cyclopes beat the metal; I was made to keep it bright. That is my work: I walk the worlds and see that the gates, and the people, hold together."))},
    {"ask": "Why do the empires quarrel?", "lines": lines(
        (K, "They pray to the same gods and sing the same songs, and so they quarrel - as brothers quarrel, more bitterly than strangers."),
        (K, "Athens loves its assembly, Sparta its discipline, Mykenai its gold, Ionia its questions, the Isles their quiet, the Minoans their memory. Each thinks its love the best."),
        (K, "And from beyond the charted lanes the Sea Peoples watch them quarrel, as wolves watch two bulls fight."))},
    {"ask": "Where are the gods now?", "lines": lines(
        (K, "Near. They do not walk among men as they did in Homer's songs, but they speak - in the oracles, in a gate that flickers, in a monster that wakes when someone has grown too proud."),
        (K, "Honour the stranger, keep your oaths, give the gods their share and do not boast. That is all they have ever asked. It is harder than it sounds."))},
    {"ask": "What is the Atrapos sector?", "lines": lines(
        (K, "The oldest corner of New Hellas, round Knossos, named for Atropos - the Fate who cuts the thread of life, and whom no god can overrule."),
        (K, "The Minoans keep secrets there older than the gates. Some say even older than me. The thread you follow begins there - and, I think, ends there too."))},
]


# --- Rules -------------------------------------------------------------------------

def _step_name(i, st):
    return "%d %s" % (i + 1, st["objective"].split(" (")[0][:42])


def build(q):
    steps = [s for s in q["steps"]]
    names = ["Not started"] + [_step_name(i, s) for i, s in enumerate(steps)] + ["Finished"]
    rules = []
    walk = []
    emp = q["empire"]

    def at(step):
        return [{"cond": "step_is", "args": {"step": step}}]

    def rewards(rw):
        out = []
        if rw.get("credits"):
            out.append({"action": "credits", "args": {"amount": rw["credits"]}})
        if rw.get("data_core"):
            out.append({"action": "give_item", "args": {"count": rw["data_core"], "item": "data_core"}})
        if rw.get("reputation"):
            out.append({"action": "reputation", "args": {"empire": emp, "amount": rw["reputation"]}})
        return out

    # The quest begins at the capital.
    rules.append({"note": "The quest begins at %s" % q["start"], "once": True,
                  "when": {"event": "docked", "args": {"station": q["start"]}}, "if": at(names[0]),
                  "then": [{"action": "dialogue", "args": {"lines": q["prologue"]}},
                           {"action": "set_step", "args": {"step": names[1]}}]})
    walk.append({"event": "docked", "args": {"station": q["start"]}})
    for i, st in enumerate(steps):
        step, nxt = names[i + 1], names[i + 2]
        last = i == len(steps) - 1
        # As it begins: objective, dialogue, what the world needs.
        begin = [{"action": "objective", "args": {"text": st["objective"]}}]
        if st.get("say"):
            begin.append({"action": "dialogue", "args": {"lines": st["say"]}})
        mk = "m%d" % (i + 1)
        group = "g%d" % (i + 1)
        if st["t"] in ("reach", "kill"):
            begin.append({"action": "marker", "args": {"marker": mk, "beacon": "signal", "place": st["place"]}})
        if st["t"] == "kill":
            for ship, n in st["ships"]:
                begin.append({"action": "spawn", "args": {"count": n, "ship_type": ship, "group": group, "place": st["place"]}})
        if st["t"] == "race":
            begin += [{"action": "set_var", "args": {"var": "late", "value": 0}},
                      {"action": "timer", "args": {"timer": "race", "seconds": st["seconds"]}}]
        rules.append({"note": "Step %d begins" % (i + 1), "once": True,
                      "when": {"event": "step", "args": {"step": step}}, "if": [], "then": begin})
        # As it ends.
        end = []
        if st.get("done"):
            end.append({"action": "dialogue", "args": {"lines": st["done"]}})
        end += rewards(st.get("reward", {}))
        if st["t"] in ("reach", "kill"):
            end.append({"action": "remove_marker", "args": {"marker": mk}})
        if last:
            for lid in q["lore"]:
                end.append({"action": "lore", "args": {"lore": lid}})
            end.append({"action": "finish", "args": {}})
        else:
            end.append({"action": "set_step", "args": {"step": nxt}})
        cond = at(step)
        t = st["t"]
        if t == "dock":
            when = {"event": "docked", "args": {"station": st["station"]}}
            walk.append({"event": "docked", "args": {"station": st["station"]}})
        elif t == "reach":
            when = {"event": "near", "args": {"distance": 600, "place": st["place"]}}
            cond = cond + [{"cond": "in_system", "args": {"system": st["system"]}}]
            walk.append({"near": st["place"], "system": st["system"]})
        elif t == "kill":
            when = {"event": "group_gone", "args": {"group": group}}
            walk.append({"kill": group, "count": sum(n for _, n in st["ships"]), "system": st["system"]})
        elif t == "deliver":
            when = {"event": "docked", "args": {"station": st["station"]}}
            for item, n in st["items"].items():
                cond = cond + [{"cond": "has_item", "args": {"count": n, "item": item}}]
            end = [{"action": "take_item", "args": {"count": n, "item": item}} for item, n in st["items"].items()] + end
            walk.append({"give": st["items"], "event": "docked", "args": {"station": st["station"]}})
        elif t == "race":
            when = {"event": "docked", "args": {"station": st["station"]}}
            # the timer running out; arriving in time (a bonus) or late (before the end rule)
            rules.append({"note": "Step %d: too late" % (i + 1), "once": True, "when": {"event": "timer", "args": {"timer": "race"}},
                          "if": at(step), "then": [{"action": "set_var", "args": {"var": "late", "value": 1}},
                                                   {"action": "message", "args": {"text": "Too late - but fly on all the same."}}]})
            rules.append({"note": "Step %d: in time" % (i + 1), "once": True, "when": when,
                          "if": at(step) + [{"cond": "var", "args": {"var": "late", "op": "=", "value": 0}}],
                          "then": [{"action": "dialogue", "args": {"lines": st["in_time"]}}] + rewards(st.get("bonus", {}))})
            rules.append({"note": "Step %d: late" % (i + 1), "once": True, "when": when,
                          "if": at(step) + [{"cond": "var", "args": {"var": "late", "op": "=", "value": 1}}],
                          "then": [{"action": "dialogue", "args": {"lines": st["late"]}}]})
            walk.append({"event": "docked", "args": {"station": st["station"]}})
        rules.append({"note": "Step %d complete" % (i + 1), "once": True, "when": when, "if": cond, "then": end})
        if t == "deliver":   # (a reminder of what's missing; after the rule above, so it's quiet once done)
            need = ", ".join("%d %s" % (n, item.replace("_", " ").title()) for item, n in st["items"].items())
            rules.append({"note": "Step %d: still needed" % (i + 1), "once": False, "when": when, "if": at(step),
                          "then": [{"action": "message", "args": {"text": "Still needed here: " + need}}]})
    return {"id": q["id"], "title": q["title"], "description": q["description"], "enabled": True,
            "empire": q["empire"], "steps": names, "rules": rules, "walkthrough": walk}


def _js(v):
    return json.dumps(v, ensure_ascii=False)


def pretty(v, indent=""):
    """DataFiles.pretty's layout (the game writes the file the same way)."""
    inner = indent + "\t"
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n" + ",\n".join(inner + _js(str(k)) + ": " + pretty(x, inner) for k, x in v.items()) + "\n" + indent + "}"
    if isinstance(v, list):
        if not v:
            return "[]"
        all_scalar = all(not isinstance(e, (dict, list)) for e in v)
        all_short = all(not isinstance(e, dict) and (not isinstance(e, list) or all(not isinstance(x, (dict, list)) for x in e)) for e in v)
        if all_scalar:
            return "[" + ", ".join(_js(e) for e in v) + "]"
        one = "[" + ", ".join(pretty(e, inner) for e in v) + "]"
        if all_short and len(one) < 90:
            return one
        return "[\n" + ",\n".join(inner + pretty(e, inner) for e in v) + "\n" + indent + "]"
    return _js(v)


def main():
    scen = json.load(open(SCEN))
    keep = [s for s in scen["scenarios"] if not str(s.get("id", "")).startswith("empire_")]
    scen["scenarios"] = keep + [build(q) for q in QUESTS]
    with open(SCEN, "w") as f:
        f.write(pretty(scen) + "\n")
    mq = json.load(open(QUEST))
    mq["giver"]["empires"] = KILON_EMPIRES
    mq["giver"]["hellas"] = KILON_HELLAS
    for q in QUESTS:
        for lid, entry in q["lore"].items():
            mq["lore"][lid] = entry
    with open(QUEST, "w") as f:
        json.dump(mq, f, indent="\t", ensure_ascii=False)
        f.write("\n")
    total = sum(len(q["steps"]) for q in QUESTS)
    print("%d quests, %d steps, %d rules, %d lore entries" % (len(QUESTS), total,
          sum(len(build(q)["rules"]) for q in QUESTS), sum(len(q["lore"]) for q in QUESTS)))


if __name__ == "__main__":
    main()
