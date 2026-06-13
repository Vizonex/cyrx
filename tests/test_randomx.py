from binascii import hexlify

from cyrx import VM, Cache, RXMiner, get_flags


def test_example() -> None:
    my_key = b"RandomX example key"
    my_input = b"RandomX example input"

    flags = get_flags()
    my_cache = Cache(flags)
    my_cache.init(my_key)
    my_machine = VM(flags, cache=my_cache)

    out_hash = my_machine.hash(my_input)
    assert (
        b"d2a4d89503447401ef6e6f30b46635b45b54f25a650c47464b5311f9d6fd4759"
        == hexlify(out_hash)
    )


def test_rxminer() -> None:
    x = RXMiner(2)
    out = x.run(
        b"d2a4d89503447401ef6e6f30b46635b45b54f25a650c47464b5311f9d6fd4759",
        b"d2a4d89503447401ef6e6f30b4663555",
    )
    assert (
        hexlify(out)
        == b"62894d19b5b129c9c7bab19171dc438446ceade7e0e8e3b1c263969e5463d9dc"
    )
