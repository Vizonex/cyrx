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

```


>[!WARNING]
>
> One Word of Caution that this library is made for eductaional purposes only 
> it has been put on pypi in order to shortcut some problems that the pyrx 
> library has failed to live up to.
> The Author of this library is not responsible for any abuse
> with this library including Crytojacking which is common amongst malware 
> authors & large botnets. Use at your own risk.

