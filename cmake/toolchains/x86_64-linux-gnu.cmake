# Cross-compile the layer for x86_64 from an ARM64 host.
#
# On ARM64 machines that run Steam through FEX (NVIDIA DGX Spark, the Steam
# snap on aarch64), the games execute as x86_64 and load an x86_64 Vulkan
# loader and ICD. The layer must be built for that ABI or the loader rejects
# it and the layer is silently never loaded.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Seeded as cache entries so callers can swap the compiler (a versioned binary,
# a launcher, clang --target=...) without editing this file. Non-FORCE keeps
# these as defaults; CMAKE_SYSTEM_NAME/PROCESSOR stay forced because the whole
# point of this file is to target x86_64.
set(CMAKE_C_COMPILER   x86_64-linux-gnu-gcc   CACHE STRING "Cross-compile C compiler")
set(CMAKE_CXX_COMPILER x86_64-linux-gnu-g++   CACHE STRING "Cross-compile C++ compiler")

# Only the multiarch sysroot may satisfy library/include searches. With BOTH,
# find_library()/find_path() also walk the host tree: verified by planting an
# aarch64 libpyrodecoy.so in /usr/lib, which BOTH resolved into the x86_64 link
# and ONLY refused. The bare /usr must stay out of CMAKE_FIND_ROOT_PATH as well -
# with it present, ONLY still finds host libraries.
#
# PROGRAM is NEVER so host build tools are used, and PACKAGE stays BOTH because
# the bundled shaderc/glslang locate host tools (python3, git) via find_package().
set(CMAKE_FIND_ROOT_PATH /usr/x86_64-linux-gnu)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
