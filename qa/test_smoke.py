"""The shortest fight a DM can run.  If this fails, nothing else will pass."""

import pytest


@pytest.mark.cross_browser
def test_a_dm_adds_monsters_and_runs_a_round(app):
    app.add("Goblin Warrior", count=2)
    app.add("Ogre")
    assert app.card_names() == ["Goblin Warrior", "Goblin Warrior 2", "Ogre"]
    assert app.card("Ogre").hp() == 68
    app.shot("roster")

    app.begin_combat()
    first = app.active_name()
    assert first in app.card_names()
    assert app.round_number() == 1

    for _ in app.card_names():
        app.next_turn()
    assert app.round_number() == 2
    assert app.active_name() == first
    app.shot("round-two")
