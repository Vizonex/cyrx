import sys

if sys.version_info >= (3, 12):
    from collections.abc import Buffer
else:
    from typing_extensions import Buffer

CYRX_FLAG_DEFAULT: int = ...
CYRX_FLAG_LARGE_PAGES: int = ...
CYRX_FLAG_HARD_AES: int = ...
CYRX_FLAG_FULL_MEM: int = ...
CYRX_FLAG_JIT: int = ...
CYRX_FLAG_SECURE: int = ...
CYRX_FLAG_ARGON2_SSSE3: int = ...
CYRX_FLAG_ARGON2_AVX2: int = ...
CYRX_FLAG_ARGON2: int = ...
CYRX_FLAG_V2: int = ...

def get_flags() -> int:
    """
    Obtains recommended flags based on the current machine in use.
    These options however do not include:
        - CYRX_FLAG_LARGE_PAGES
        - CYRX_FLAG_FULL_MEM
        - CYRX_FLAG_SECURE

    :returns: recommended flags
    """
    ...

def dataset_item_count() -> int:
    """
    Gets the number of items contained in a given dataset.
    Know however that the size may vary depending on system's
    current arch.
    """
    ...

class Cache:
    def __init__(self, flags: int = 0): ...
    def init(self, key: Buffer) -> None:
        """
        Initializes the cache memory using a provided key.

        :param key: the key to initializes

        :raises ValueError: if key is empty, it really shouldn't be.
        :raises TypeError: if object doesn't support the buffer protocol.
        :raises BufferError: raised if buffer doesn't support the
            existing flag.
        """
    def get_memory(self) -> bytes:
        """
        Obtains a pointer to the interal memory buffer of the cache structure.
        """

class Dataset:
    def __init__(self, flags: int = 0): ...
    def init(self, cache: Cache, start_item: int = ..., item_count: int = ...) -> None:
        """
        Initializes dataset items.

        This may be done by several calls in overlapping threads as needed.

        :param cache: the cache to a previously allocated dataset structure.
        :param start: the start position to initalize off of defaults to 0
        :param end: the ending position to initialize off of defaults to
            `randomx_dataset_item_count()`

        :raises ValueError: raised when randomx's rules about the start and ending
            position aren't met.
        """
        ...
    def get_memory(self) -> bytes:
        """
        Obtains the internal memory of the underlying randomx dataset structure.
        """
        ...

class VM:
    def __init__(
        self, flags: int = 0, cache: Cache | None = None, dataset: Dataset | None = None
    ) -> None: ...
    def set_cache(self, cache: Cache) -> None:
        """
        Reinitializes a virtual machine with a new Cache.
        This function should get called anytime the cache is
        reinitialized with a new key.

        :param cache: the new cache to set.
        """
        ...
    def set_dataset(self, dataset: Dataset) -> None:
        """
        Reinitializes a virtual machine with a new Dataset.

        :param dataset: the new dataset to set.
        """
        ...
    def hash(self, input: object) -> bytes: ...
    def hash_first(self, input: object) -> None: ...
    def hash_next(self, input: object) -> bytes: ...
    def hash_last(self) -> bytes: ...

class RXMiner:
    """
    Used for being a rather optimized version of a crypto mining
    class with minimal required things to setup.
    """
    def __init__(
        self,
        threads: int = ...,
        large_pages: bool = ...,
        jit: bool = ...,
        secure: bool = ...,
        ssse3: bool = ...,
        avx2: bool = ...,
        argon2: bool = ...,
        v2: bool = ...,
    ) -> None: ...
    def run(self, data: Buffer, seed: Buffer) -> bytes:
        """
        Runs a single cycle normally known as a `slow_hash`
        function in other code implementations. A simpler name
        was chosen to be a little bit cleaner and less confusing
        (especially for newcommers).

        :param data: the data buffer being inputted.
        :param seed: the current seed
            if different, the current seed will be updated
            and the dataset will be initalized from multiple
            threads if multiple were provided otherwise it runs
            off of a single thread.

        :returns: a computed hash from the randomx virtual machine.
        """
        ...

class SeedHeights:
    current: int
    next: int

class SeedHeight:
    def __init__(self, lag: int = ..., blocks: int = ...): ...
    @property
    def lag(self) -> int:
        """obtains currently set epoch lag"""

    @lag.setter
    def lag(self, value: int) -> None: ...
    @property
    def blocks(self) -> int:
        """obtains the current number of blocks to use"""

    @blocks.setter
    def blocks(self, value: int) -> None: ...
    def get_current(self, height: int) -> int: ...
    def get_pair(self, height: int) -> SeedHeights: ...
