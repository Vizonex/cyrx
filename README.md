# cyrx
A Sequal to pyrx the randomX crypto mining library.
This one plans to actually have a pypi package associated to it.
It shares the resemblance of the actual randomx api rather 
than with pyrx which contains only a few functions and that was it for it.

## How to use
```python
from cyrx import get_flags, Cache, VM

from binascii import hexlify

def main():
    my_key = b"RandomX example key"
    my_input = b"RandomX example input"

    flags = get_flags()
    my_cache = Cache(flags)
    my_cache.init(my_key)
    my_machine = VM(flags, cache=my_cache)

    out_hash = my_machine.hash(my_input)
    print(hexlify(out_hash))

if __name__ == "__main__":
    main()
```

```python
from cyrx import RXMiner

def main() -> None:
    x = RXMiner(2) # 2 threads in this case...
    out = x.run(
        b"d2a4d89503447401ef6e6f30b46635b45b54f25a650c47464b5311f9d6fd4759",
        b"d2a4d89503447401ef6e6f30b4663555",
    )
    assert (
        hexlify(out)
        == b"62894d19b5b129c9c7bab19171dc438446ceade7e0e8e3b1c263969e5463d9dc"
    )
if __name__ == "__main__":
    main()
```


>[!WARNING]
>
> One Word of Caution that this library is made for eductaional purposes only 
> it has been put on pypi in order to shortcut some problems that the pyrx 
> library has failed to live up to.
> The Author of this library is not responsible for any abuse
> with this library including Crytojacking which is common amongst malware 
> authors & large botnets. Use at your own risk.

