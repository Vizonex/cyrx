# cython: language_level = 3, language = c++
from libc.stdint cimport uint8_t, uint64_t
from ._randomx cimport *
from cpython.bytes cimport PyBytes_FromString, PyBytes_FromStringAndSize
from cpython.buffer cimport PyObject_GetBuffer, PyBUF_SIMPLE, PyBuffer_Release
from cpython.mem cimport PyMem_Malloc, PyMem_Free, PyMem_Realloc
from cython cimport parallel
from libc.string cimport memcpy
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

def get_flags():
    return randomx_get_flags()

def dataset_item_count():
    return randomx_dataset_item_count()

cdef int get_buffer(object obj, Py_buffer* view):
    return PyObject_GetBuffer(obj, view, PyBUF_SIMPLE)


cdef class Cache:
    cdef:
        randomx_cache* cache

    def __init__(self, uint8_t flags = RANDOMX_FLAG_DEFAULT) -> None:
        cdef randomx_cache* cache = randomx_alloc_cache(<randomx_flags>flags)
        if cache == NULL:
            raise MemoryError
        
        self.cache = cache
    
    def init(self, object key):
        cdef Py_buffer view

        if len(key) <= 0:
            raise ValueError("key cannot be empty")
        
        if get_buffer(key, &view) < 0:
            raise
        
        with nogil:
            randomx_init_cache(self.cache, view.buf, <size_t>view.len)
        
        PyBuffer_Release(&view)

    def get_memory(self):
        return PyBytes_FromString(<char*>randomx_get_cache_memory(self.cache))

    def __dealloc__(self):
        if self.cache != NULL:
            randomx_release_cache(self.cache)


cdef class Dataset:
    cdef randomx_dataset* dataset
    def __cinit__(self, randomx_flags flags = RANDOMX_FLAG_DEFAULT) -> None:
        cdef randomx_dataset* dataset = randomx_alloc_dataset(flags)
        if dataset == NULL:
            raise MemoryError
    
    def init(self, Cache cache, unsigned long start_item, unsigned long item_count):
        cdef unsigned long dataset_item_count = randomx_dataset_item_count()
        if not ((start_item < dataset_item_count) and (item_count <= dataset_item_count)):
            raise ValueError("start_item should be less than the dataset item count same with the item_count")

        with nogil:
            randomx_init_dataset(self.dataset, cache.cache, start_item, item_count)


    def get_memory(self):
        return PyBytes_FromString(<char*>randomx_get_dataset_memory(self.dataset))

    def __dealloc__(self):
        if self.dataset != NULL:
            randomx_release_dataset(self.dataset)


cdef class VM:
    cdef randomx_vm* vm

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

    def __dealloc__(self):
        if self.vm != NULL:
            randomx_destroy_vm(self.vm)

    def set_cache(self, Cache cache):
        randomx_vm_set_cache(self.vm, cache.cache)
    
    def set_dataset(self, Dataset dataset):
        randomx_vm_set_dataset(self.vm, dataset.dataset)
    
    def hash(self, object input):
        cdef Py_buffer view
        cdef char out[32]

        if not input:
            raise ValueError("input cannot be empty")
        
        if get_buffer(input, &view) < 0:
            raise
        
        with nogil:
            randomx_calculate_hash(self.vm, view.buf, <size_t>view.len, out)
        
        PyBuffer_Release(&view)
        return PyBytes_FromStringAndSize(out, 32)

    def hash_first(self, object input):
        cdef Py_buffer view

        if not input:
            raise ValueError("input cannot be empty")
        
        if get_buffer(input, &view) < 0:
            raise
        
        with nogil:
            randomx_calculate_hash_first(self.vm, view.buf, <size_t>view.len)

        PyBuffer_Release(&view)

    def hash_next(self, object input):
        cdef Py_buffer view
        cdef char out[32]

        if not input:
            raise ValueError("input cannot be empty")
        
        if get_buffer(input, &view) < 0:
            raise
        
        with nogil:
            randomx_calculate_hash_next(self.vm, view.buf, <size_t>view.len, out)
    
        return PyBytes_FromStringAndSize(out, 32)
    
    def hash_last(self):
        cdef char out[32]

        with nogil:
            randomx_calculate_hash_last(self.vm, out)
        return PyBytes_FromStringAndSize(out, 32)

    # TODO:
    # def calculate_commitment(self, object input, object  ):


# Based off https://github.com/EpicCash/randomx-rust/blob/master/src/types.rs

cdef struct rx_seed:
    uint64_t start
    uint64_t end

cdef class RXMiner:
    cdef:
        object seed
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
        cdef Py_buffer view

        if threads == 0:
            threads = 1

        self.n_threads = 0
        self.flags = RANDOMX_FLAG_DEFAULT

        if large_pages:
            self.flags |= RANDOMX_FLAG_LARGE_PAGES
        
        if jit:
            self.flags |= RANDOMX_FLAG_JIT
        
        if secure:
            self.flags |= RANDOMX_FLAG_SECURE
        
        if ssse3:
            self.flags |= RANDOMX_FLAG_ARGON2_SSSE3
        
        if avx2:
            self.flags |= RANDOMX_FLAG_ARGON2_AVX2
        
        if argon2:
            self.flags |= RANDOMX_FLAG_ARGON2
        
        if v2:
            self.flags |= RANDOMX_FLAG_V2

        
        self.seed = None
        self.dataset = Dataset(<randomx_flags>self.flags)
        self.cache = Cache(<randomx_flags>self.flags)
        self.vm = VM(<randomx_flags>self.flags, self.cache, self.dataset)
        if self._init_threads(threads) < 0:
            raise MemoryError

    cdef int init_seed(self, object seed):
        if len(seed) != 32:
            raise ValueError("seeds should be exactly 32 bits")
        cdef memoryview _seed = memoryview(seed)
        if _seed != self.seed:
            self.seed = _seed
            self.cache.init(_seed)
            return False
        return True

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
 
    def run(self, object data, object seed):
        cdef randomx_cache* cache = self.cache.cache
        cdef randomx_dataset* dataset = self.dataset.dataset
        cdef rx_seed* workers = self.workers
        cdef uint8_t t
        cdef memoryview _data = memoryview(data)

        if not self.init_seed(seed):
            if self.n_threads == 1:
                self.dataset.init(self.cache, 0, randomx_dataset_item_count())
            else:
                with nogil:
                    for t in parallel.prange(self.n_threads, num_threads=self.n_threads):
                        randomx_init_dataset(dataset, cache, workers[t].start, workers[t].end)

        return self.vm.hash(_data)


       


        
        





