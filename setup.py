import os
import platform
import shutil
import subprocess
import sys
from typing import ClassVar

from setuptools import Extension, setup
from setuptools.command.build_ext import build_ext

use_system_lib = bool(int(os.environ.get("CYRX_USE_SYSTEM_LIB", 0)))


def is_windows_11_arm() -> bool:
    """Checks if we are using windows-11-arm"""

    is_arm = platform.machine() == "ARM64"

    version = platform.version()
    build = version.split(".")[2] if len(version.split(".")) > 2 else "0"
    is_win11_build = platform.release() == "10" and int(build) >= 22000

    return is_arm and is_win11_build


class cyrx_build_ext(build_ext):
    # Brought over from winloop since these can be very useful.
    user_options: ClassVar[list[tuple[str, str | None, str]]] = [
        *build_ext.user_options,
        ("cython-always", None, "run cythonize() even if .c files are present"),
        (
            "cython-annotate",
            None,
            "Produce a colorized HTML version of the Cython source.",
        ),
        ("cython-directives=", None, "Cythion compiler directives"),
    ]

    def initialize_options(self):
        self.cython_always = False
        self.cython_annotate = False
        self.cython_directives = None
        super().initialize_options()

    def add_include_dir(self, dir, force=False):
        if use_system_lib and not force:
            return
        dirs = self.compiler.include_dirs
        dirs.insert(0, dir)
        self.compiler.set_include_dirs(dirs)

    def build_extensions(self):
        if use_system_lib:
            self.compiler.add_library("randomx")
            build_ext.build_extensions(self)
            return

        cmake_cmd = shutil.which("cmake")

        if not cmake_cmd:
            raise RuntimeError("cyrx requires cmake")

        randomx_dir = os.path.join("vendor")
        build_temp = os.path.abspath(os.path.join(self.build_temp, "cyrx-build"))
        install_dir = os.path.abspath(os.path.join(self.build_temp, "cyrx-install"))
        os.makedirs(build_temp, exist_ok=True)
        os.makedirs(install_dir, exist_ok=True)

        cmake_args = [
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_CONFIGURATION_TYPES=Release",
            f"-DCMAKE_INSTALL_PREFIX={install_dir}",
        ]

        if is_windows_11_arm():
            cmake_args.append("-DARM64")

        print(f"Configuring randomx with CMake in {build_temp}")
        subprocess.check_call(
            [cmake_cmd, os.path.abspath(randomx_dir), *cmake_args], cwd=build_temp
        )

        print("Building randomx...")
        build_args = ["--build", ".", "--config", "Release"]

        subprocess.check_call([cmake_cmd, *build_args], cwd=build_temp)

        install_args = ["--install", ".", "--config", "Release"]
        subprocess.check_call([cmake_cmd, *install_args], cwd=build_temp)

        if sys.platform == "win32":
            # Windows libraries
            possible_paths = [
                os.path.join(install_dir, "lib", "randomx.lib"),
                os.path.join(install_dir, "lib", "randomx_static.lib"),
                os.path.join(install_dir, "lib", "librandomx.a"),  # MinGW
            ]
        else:
            possible_paths = [
                os.path.join(install_dir, "lib", "librandomx.a"),
                os.path.join(install_dir, "lib64", "librandomx.a"),
            ]

        lib_path = None
        for path in possible_paths:
            if os.path.exists(path):
                lib_path = path
                break

        # print("==== DEBUG ====")
        # print(lib_path)

        if not lib_path:
            raise RuntimeError(
                f"Could not find installed randomx library in {install_dir}.\n"
                f"Checked: {', '.join(possible_paths)}"
            )

        self.extensions[0].extra_objects = [lib_path]

        if sys.platform == "win32":
            self.compiler.add_library("Advapi32")

        self.add_include_dir("vendor/src")
        self.add_include_dir("vendor/src/asm")
        self.add_include_dir("vendor/src/blake2")
        build_ext.build_extensions(self)

    def finalize_options(self):
        need_cythonize = self.cython_always
        cfiles = {}

        for extension in self.distribution.ext_modules:
            for i, sfile in enumerate(extension.sources):
                if sfile.endswith(".pyx"):
                    prefix, _ = os.path.splitext(sfile)
                    cfile = prefix + ".c"

                    if os.path.exists(cfile) and not self.cython_always:
                        extension.sources[i] = cfile
                    else:
                        if os.path.exists(cfile):
                            cfiles[cfile] = os.path.getmtime(cfile)
                        else:
                            cfiles[cfile] = 0
                        need_cythonize = True

        if need_cythonize:
            # import pkg_resources

            # Double check Cython presence in case setup_requires
            # didn't go into effect (most likely because someone
            # imported Cython before setup_requires injected the
            # correct egg into sys.path.
            try:
                import Cython  # noqa: F401
            except ImportError:
                raise RuntimeError(
                    "please install cython to compile cyares from source"
                )

            from Cython.Build import cythonize

            directives = {}
            if self.cython_directives:
                for directive in self.cython_directives.split(","):
                    k, _, v = directive.partition("=")
                    if v.lower() == "false":
                        v = False
                    if v.lower() == "true":
                        v = True
                    directives[k] = v
                self.cython_directives = directives

            self.distribution.ext_modules[:] = cythonize(
                self.distribution.ext_modules,
                compiler_directives=directives,
                annotate=self.cython_annotate,
                emit_linenums=self.debug,
                # Try using a cache to help with compiling as well...
                cache=True,
            )

        return super().finalize_options()


if __name__ == "__main__":
    setup(
        ext_modules=[Extension("cyrx._cyrx", sources=["src/cyrx/_cyrx.pyx"])],
        cmdclass={"build_ext": cyrx_build_ext},
    )
