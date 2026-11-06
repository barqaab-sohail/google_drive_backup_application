import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _VolumePathN = Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _VolumePathD = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _SpaceN =
    Int32 Function(
      Pointer<Utf16>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );
typedef _SpaceD =
    int Function(
      Pointer<Utf16>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );

class DiskInfo {
  final String? identity;
  final int? freeBytes;
  const DiskInfo(this.identity, this.freeBytes);
}

DiskInfo inspectDisk(String path) {
  if (!Platform.isWindows) return const DiskInfo(null, null);
  final kernel = DynamicLibrary.open('kernel32.dll');
  final volumePath = kernel.lookupFunction<_VolumePathN, _VolumePathD>(
    'GetVolumePathNameW',
  );
  final volumeName = kernel.lookupFunction<_VolumePathN, _VolumePathD>(
    'GetVolumeNameForVolumeMountPointW',
  );
  final diskSpace = kernel.lookupFunction<_SpaceN, _SpaceD>(
    'GetDiskFreeSpaceExW',
  );
  final input = path.toNativeUtf16();
  final mount = calloc<Uint16>(32768).cast<Utf16>();
  final name = calloc<Uint16>(1024).cast<Utf16>();
  final free = calloc<Uint64>(),
      total = calloc<Uint64>(),
      totalFree = calloc<Uint64>();
  try {
    String? identity;
    if (volumePath(input, mount, 32768) != 0 &&
        volumeName(mount, name, 1024) != 0) {
      identity = name.toDartString();
    }
    final ok = diskSpace(input, free, total, totalFree) != 0;
    return DiskInfo(identity, ok ? free.value : null);
  } finally {
    calloc.free(input);
    calloc.free(mount);
    calloc.free(name);
    calloc.free(free);
    calloc.free(total);
    calloc.free(totalFree);
  }
}
