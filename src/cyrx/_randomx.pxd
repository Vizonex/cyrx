
cdef extern from "randomx.h" nogil:
    struct randomx_vm:
        pass
    struct randomx_cache:
        pass
    struct randomx_dataset:
        pass
    enum randomx_flags:
        RANDOMX_FLAG_DEFAULT = 0
        RANDOMX_FLAG_LARGE_PAGES = 1
        RANDOMX_FLAG_HARD_AES = 2
        RANDOMX_FLAG_FULL_MEM = 4
        RANDOMX_FLAG_JIT = 8
        RANDOMX_FLAG_SECURE = 16
        RANDOMX_FLAG_ARGON2_SSSE3 = 32
        RANDOMX_FLAG_ARGON2_AVX2 = 64
        RANDOMX_FLAG_ARGON2 = 96
        RANDOMX_FLAG_V2 = 128
    ctypedef randomx_flags randomx_flags
    ctypedef randomx_dataset randomx_dataset
    ctypedef randomx_cache randomx_cache
    ctypedef randomx_vm randomx_vm
    randomx_flags randomx_get_flags()
    randomx_cache* randomx_alloc_cache(randomx_flags flags)
    void randomx_init_cache(randomx_cache* cache, const void* key, size_t keySize)
    void* randomx_get_cache_memory(randomx_cache* cache)
    void randomx_release_cache(randomx_cache* cache)
    randomx_dataset* randomx_alloc_dataset(randomx_flags flags)
    unsigned long randomx_dataset_item_count()
    void randomx_init_dataset(randomx_dataset* dataset, randomx_cache* cache, unsigned long startItem, unsigned long itemCount)
    void* randomx_get_dataset_memory(randomx_dataset* dataset)
    void randomx_release_dataset(randomx_dataset* dataset)
    randomx_vm* randomx_create_vm(randomx_flags flags, randomx_cache* cache, randomx_dataset* dataset)
    void randomx_vm_set_cache(randomx_vm* machine, randomx_cache* cache)
    void randomx_vm_set_dataset(randomx_vm* machine, randomx_dataset* dataset)
    void randomx_destroy_vm(randomx_vm* machine)
    void randomx_calculate_hash(randomx_vm* machine, const void* input, size_t inputSize, void* output)
    void randomx_calculate_hash_first(randomx_vm* machine, const void* input, size_t inputSize)
    void randomx_calculate_hash_next(randomx_vm* machine, const void* nextInput, size_t nextInputSize, void* output)
    void randomx_calculate_hash_last(randomx_vm* machine, void* output)
    void randomx_calculate_commitment(const void* input, size_t inputSize, const void* hash_in, void* com_out)
