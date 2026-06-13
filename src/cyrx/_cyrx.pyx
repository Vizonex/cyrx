# cython: freethreading_compatible = True
# distutils: language = c++
from libc.stdint cimport uint8_t, uint64_t
from ._randomx cimport *
from cpython.bytes cimport PyBytes_FromString, PyBytes_FromStringAndSize
from cpython.buffer cimport PyObject_GetBuffer, PyBUF_SIMPLE, PyBuffer_Release
from cpython.mem cimport PyMem_Malloc, PyMem_Free, PyMem_Realloc
from cpython.exc cimport PyErr_SetString
from cython cimport parallel
cimport cython

cpdef enum:
    CYRX_FLAG_DEFAULT = 0
cpdef enum:
    CYRX_FLAG_LARGE_PAGES = 1
cpdef enum:
    CYRX_FLAG_HARD_AES = 2
cpdef enum:
    CYRX_FLAG_FULL_MEM = 4
cpdef enum:
    CYRX_FLAG_JIT = 8
cpdef enum:
    CYRX_FLAG_SECURE = 16
cpdef enum:
    CYRX_FLAG_ARGON2_SSSE3 = 32
cpdef enum:
    CYRX_FLAG_ARGON2_AVX2 = 64
cpdef enum:
    CYRX_FLAG_ARGON2 = 96
cpdef enum:
    CYRX_FLAG_V2 = 128


# NOTE: All recastings to randomx_flags must not be exposed to python
# This is due to the way the compilers on unix systems work
# so extra care MUST be taken to ensure no exposals happen
# recasts are used to help workaround these problems...

def get_flags():
    """
    Obtains recommended flags based on the current machine in use.
    These options however do not include:
        - CYRX_FLAG_LARGE_PAGES
        - CYRX_FLAG_FULL_MEM
        - CYRX_FLAG_SECURE

    :returns: recommended flags
    """
    return <uint8_t>randomx_get_flags()

def dataset_item_count():
    """
    Gets the number of items contained in a given dataset.
    Know however that the size may vary depending on system's 
    current arch.
    """
    return randomx_dataset_item_count()

# mostly a lazy shortcut for reaching PyObject_GetBuffer with PyBUF_SIMPLE
# added in for us.
cdef int get_buffer(object obj, Py_buffer* view):
    return PyObject_GetBuffer(obj, view, PyBUF_SIMPLE)


# NOTE: Throw an issue if you think this error is too vauge and 
# we can adjust the naming or allow custom parameter names to be utilized.
cdef int extract_input(object buf, Py_buffer* view):
    if not buf:
        PyErr_SetString(ValueError, "input buffer can't be empty or None")
        return -1
    return PyObject_GetBuffer(buf, view, PyBUF_SIMPLE)


cdef class Cache:
    cdef:
        randomx_cache* cache

    def __init__(self, uint8_t flags = RANDOMX_FLAG_DEFAULT) -> None:
        cdef randomx_cache* cache = randomx_alloc_cache(<randomx_flags>flags)
        if cache == NULL:
            raise MemoryError
        
        self.cache = cache
    
    cpdef object init(self, object key):
        """
        Initializes the cache memory using a provided key.
        
        :param key: the key to initializes

        :raises ValueError: if key is empty, it really shouldn't be.
        :raises TypeError: if object doesn't support the buffer protocol.
        :raises BufferError: raised if buffer doesn't support the 
            existing flag.
        """

        cdef Py_buffer view

        if extract_input(key, &view) < 0:
            raise
        
        with nogil:
            randomx_init_cache(self.cache, view.buf, <size_t>view.len)
        
        PyBuffer_Release(&view)

    def get_memory(self):
        """
        Obtains a pointer to the interal memory buffer of the cache structure.
        """
        return PyBytes_FromString(<char*>randomx_get_cache_memory(self.cache))

    def __dealloc__(self):
        if self.cache != NULL:
            randomx_release_cache(self.cache)


cdef class Dataset:
    cdef randomx_dataset* dataset

    def __init__(self, uint8_t flags = RANDOMX_FLAG_DEFAULT) -> None:
        cdef randomx_dataset* dataset = randomx_alloc_dataset(<randomx_flags>flags)
        if dataset == NULL:
            raise MemoryError
    
    
    cpdef object init(self, Cache cache, unsigned long start = 0, unsigned long end = randomx_dataset_item_count() - 1):
        """
        Initializes dataset items.

        This may be done by several calls in overlapping threads as needed.
        
        :param cache: the cache to a previously allocated dataset structure.
        :param start: the start position to initalize off of defaults to 0
        :param end: the ending position to initialize off of defaults to `randomx_dataset_item_count()`
        
        :raises ValueError: raised when randomx's rules about the start and ending position aren't met.
        """
        cdef unsigned long dataset_item_count = randomx_dataset_item_count()
        if not ((start < dataset_item_count) and (end <= dataset_item_count)):
            raise ValueError("start should be less than the dataset item count and end should not exceed the dataset item count.")

        with nogil:
            randomx_init_dataset(self.dataset, cache.cache, start, end)


    def get_memory(self):
        """
        Obtains the internal memory of the underlying randomx dataset structure.
        """
        return PyBytes_FromString(<char*>randomx_get_dataset_memory(self.dataset))

    def __dealloc__(self):
        if self.dataset != NULL:
            randomx_release_dataset(self.dataset)


cdef class VM:
    cdef randomx_vm* vm
    cdef uint8_t flags

    def __init__(
        self,
        uint8_t flags = RANDOMX_FLAG_DEFAULT, 
        object cache = None,
        object dataset = None
    ):  
        cdef randomx_vm* vm
        cdef randomx_dataset* rx_dataset = NULL
        cdef randomx_cache* rx_cache = NULL
        cdef bint full_mem = (flags & RANDOMX_FLAG_FULL_MEM)
        if not ((cache is not None) or full_mem):
            raise RuntimeError("to create a vm the cache must not be empty otherwise it requires CYRX_FLAG_FULL_MEM")
        
        if not ((dataset is not None) or not full_mem):
            raise RuntimeError("to create a vm if CYRX_FLAG_FULL_MEM is used there should not be a dataset avalible")

        if cache is not None:
            rx_cache = (<Cache>cache).cache
        if dataset is not None:
            rx_dataset = (<Dataset>dataset).dataset
        
        with nogil:
            vm = randomx_create_vm(<randomx_flags>flags, rx_cache, rx_dataset)
        if vm == NULL:
            raise MemoryError
        self.vm = vm
        self.flags = flags

    def __dealloc__(self):
        if self.vm != NULL:
            randomx_destroy_vm(self.vm)

    cpdef object set_cache(self, Cache cache):
        """
        Reinitializes a virtual machine with a new Cache.
        This function should get called anytime the cache is 
        reinitialized with a new key.

        :param cache: the new cache to set.
        """
        with nogil:
            randomx_vm_set_cache(self.vm, cache.cache)

    cpdef object set_dataset(self, Dataset dataset):
        """
        Reinitializes a virtual machine with a new Dataset.

        :param dataset: the new dataset to set. 
        """
        with nogil:
            randomx_vm_set_dataset(self.vm, dataset.dataset)
    
    cpdef bytes hash(self, object input):
        cdef Py_buffer view
        cdef char out[32]

        if extract_input(input, &view) < 0:
            raise
        
        with nogil:
            randomx_calculate_hash(self.vm, view.buf, <size_t>view.len, out)
        
        PyBuffer_Release(&view)
        return PyBytes_FromStringAndSize(out, 32)

    def hash_first(self, object input):
        cdef Py_buffer view

        if extract_input(input, &view) < 0:
            raise
        
        with nogil:
            randomx_calculate_hash_first(self.vm, view.buf, <size_t>view.len)

        PyBuffer_Release(&view)

    def hash_next(self, object input):
        cdef Py_buffer view
        cdef char out[32]

        if extract_input(input, &view) < 0:
            raise

        with nogil:
            randomx_calculate_hash_next(self.vm, view.buf, <size_t>view.len, out)
    
        return PyBytes_FromStringAndSize(out, 32)
    
    def hash_last(self):
        cdef char out[32]

        with nogil:
            randomx_calculate_hash_last(self.vm, out)
        return PyBytes_FromStringAndSize(out, 32)



# Inspired off https://github.com/EpicCash/randomx-rust/blob/master/src/types.rs

cdef struct rx_seed:
    uint64_t start
    uint64_t end

cdef class RXMiner:
    """
    Used for being a rather optimized version of a crypto mining
    class with minimal required things to setup.
    """
    cdef:
        object _seed
        Cache cache
        Dataset dataset
        VM vm
        rx_seed* workers
        uint8_t n_threads
        uint8_t flags

        
    def __init__(
        self,
        uint8_t threads = 2,
        bint large_pages = False,
        bint jit = False,
        bint secure = False,
        bint ssse3 = False,
        bint avx2 = False,
        bint argon2 = False,
        bint v2 = False
    ):

        if threads == 0:
            threads = 1

        self.n_threads = 0
        self.flags = RANDOMX_FLAG_DEFAULT

        if large_pages:
            self.flags |= <uint8_t>RANDOMX_FLAG_LARGE_PAGES
        
        if jit:
            self.flags |= <uint8_t>RANDOMX_FLAG_JIT
        
        if secure:
            self.flags |= <uint8_t>RANDOMX_FLAG_SECURE
        
        if ssse3:
            self.flags |= <uint8_t>RANDOMX_FLAG_ARGON2_SSSE3
        
        if avx2:
            self.flags |= <uint8_t>RANDOMX_FLAG_ARGON2_AVX2
        
        if argon2:
            self.flags |= <uint8_t>RANDOMX_FLAG_ARGON2
        
        if v2:
            self.flags |= <uint8_t>RANDOMX_FLAG_V2

        
        self._seed = None
        self.dataset = Dataset(self.flags)
        self.cache = Cache(self.flags)
        self.vm = VM(self.flags, self.cache, self.dataset)
        if self._init_threads(threads) < 0:
            raise MemoryError

    cdef int init_seed(self, object seed):
        # NOTE: Memoryview is the safest thing to use 
        # as it is carrying a Py_buffer that it 
        # will remeber to release when complete. 
        # it is used here mostly as a safety measure 
        # to ensure the seed is compatable. with any 
        # buffer object examples: bytearray, bytes, array.array.
        cdef memoryview _seed = memoryview(seed)
        if _seed == self._seed:
            # No extra actions nessesary.
            return True
        
        self.cache.init(seed)

        # update vm like the randomx documentation 
        # suggests doing after updating the key.
        # will use the C function directly since were not 
        # working with python buffers directly in this section.

        with nogil:
            randomx_vm_set_cache(self.vm.vm, self.cache.cache)

        self._seed = seed
        return True
    
    @property
    def seed(self): # -> memoryview | None
        """the current seed in use. 
        To change the current seed in use, 
        use the :function:`.run` function."""
        return self._seed

 
    @property
    def threads(self): # -> int
        """the current number of threads in use."""
        return self.n_threads

    @cython.cdivision(True)
    cdef int _init_threads(self, uint8_t threads):
        cdef rx_seed* workers
        if self.n_threads == threads:
            return 0
        
        if self.workers != NULL:
            workers = <rx_seed*>PyMem_Realloc(self.workers, <size_t>threads * sizeof(rx_seed))
            if workers == NULL:
                return -1
            self.workers = workers
        else:
            self.workers = <rx_seed*>PyMem_Malloc(<size_t>threads *  sizeof(rx_seed))
            if self.workers == NULL:
                return -1

        cdef uint64_t count = randomx_dataset_item_count()
        cdef uint64_t start = 0
        cdef uint64_t amount, remainder

        amount = count / <uint64_t>threads
        remainder = count % <uint64_t>threads
        
        for n, i in enumerate(range(amount, count, amount)):
            self.workers[n].start = start
            self.workers[n].end = i
            start = i

        # stack the cherry on top...
        self.workers[threads - 1].end += remainder
        return 0

    def __dealloc__(self):
        if self.workers != NULL:
            PyMem_Free(self.workers)
 
    def run(self, object data, object seed): # -> bytes
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
        cdef randomx_cache* cache = self.cache.cache
        cdef randomx_dataset* dataset = self.dataset.dataset
        cdef rx_seed* workers = self.workers
        cdef memoryview _data = memoryview(data)
        cdef uint8_t t

        if not self.init_seed(seed):
            if self.n_threads == 1:
                self.dataset.init(self.cache, 0, randomx_dataset_item_count())
            else:
                with nogil:
                    for t in parallel.prange(self.n_threads, num_threads=self.n_threads):
                        randomx_init_dataset(dataset, cache, workers[t].start, workers[t].end)

        return self.vm.hash(_data)


# Seems to be of importance to tools like 
# https://github.com/monero-project/monero/blob/master/src/crypto/rx-slow-hash.c#L141
# I wrote my own version since it's seems to be very simplistic math 
# but feel free to throw an issue if licensing is a concern.

DEF SEEDHASH_EPOCH_BLOCKS = 2048
DEF SEEDHASH_EPOCH_LAG = 64


cdef extern from *:
    """

// Copyright (c) 2019-2024, The Monero Project
//
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification, are
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this list of
//    conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice, this list
//    of conditions and the following disclaimer in the documentation and/or other
//    materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its contributors may be
//    used to endorse or promote products derived from this software without specific
//    prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
// THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
// STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
// THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

uint64_t rx_seedhight(const uint64_t height,const uint64_t blocks,const uint64_t lag) {
    return (height <= blocks+lag) ? 0 :
                       (height - lag - 1) & ~(blocks-1);
}
static inline int is_power_of_2(uint64_t n) { return n && (n & (n-1)) == 0; }
    """
    uint64_t rx_seedhight(const uint64_t height,const uint64_t blocks,const uint64_t lag) noexcept nogil
    bint is_power_of_2(uint64_t n) nogil

@cython.dataclasses.dataclass
cdef class SeedHeights:
    cdef:
        readonly uint64_t current
        readonly uint64_t next
    
    
 
cdef class SeedHeight:
    """Helps with calculation of different seed hights related things"""
    cdef:
        uint64_t _lag
        uint64_t _blocks
    
    def __init__(self, uint64_t lag = SEEDHASH_EPOCH_LAG, uint64_t blocks = SEEDHASH_EPOCH_BLOCKS) -> None:
        self._lag = lag
        self._blocks = blocks

    @property
    def lag(self):
        """obtains currently set epoch lag"""
        return self._lag
    
    @lag.setter
    def lag(self, uint64_t value):
        if value > SEEDHASH_EPOCH_LAG or (not is_power_of_2(value)):
            self._lag = SEEDHASH_EPOCH_LAG
        elif value:
            self._lag = value
        else:
            self._lag = SEEDHASH_EPOCH_LAG

    @property
    def blocks(self):
        """obtains the current number of blocks to use"""
        return self._blocks
    
    @blocks.setter
    def blocks(self, uint64_t value):
        if value < 2 or value > SEEDHASH_EPOCH_BLOCKS or (not is_power_of_2(value)):
            self._blocks = SEEDHASH_EPOCH_BLOCKS
        elif value:
            self._lag = value
        else:
            self._lag = SEEDHASH_EPOCH_BLOCKS

    cpdef uint64_t get_current(self, const uint64_t height):
        return rx_seedhight(height, self._blocks, self._lag)

    cpdef SeedHeights get_pair(self, const uint64_t height):
        return SeedHeights(self.get_current(height), height + self._lag)


 