#!/usr/bin/env python3
"""Trim CAF file using CoreAudio Python bindings."""
import ctypes
import ctypes.util
import sys

# Load AudioToolbox framework
at = ctypes.cdll.LoadLibrary(ctypes.util.find_library('AudioToolbox'))
cf = ctypes.cdll.LoadLibrary(ctypes.util.find_library('CoreFoundation'))

# Define types
CFURLRef = ctypes.c_void_p
AudioFileID = ctypes.c_void_p
ExtAudioFileID = ctypes.c_void_p

# Define constants
kCFURLPOSIXPathStyle = 0

# Function signatures
cf.CFURLCreateWithFileSystemPath.restype = CFURLRef
cf.CFURLCreateWithFileSystemPath.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_bool]
cf.CFRelease.argtypes = [ctypes.c_void_p]

at.ExtAudioFileOpenURL.restype = ctypes.c_int
at.ExtAudioFileOpenURL.argtypes = [CFURLRef, ctypes.POINTER(ExtAudioFileID)]

# We need to:
# 1. Open the source CAF file
# 2. Read audio data
# 3. Trim it
# 4. Write to new file

def trim_caf(input_path, output_path, max_seconds):
    try:
        # Create URLs
        in_url = cf.CFURLCreateWithFileSystemPath(None, input_path.encode(), kCFURLPOSIXPathStyle, False)
        out_url = cf.CFURLCreateWithFileSystemPath(None, output_path.encode(), kCFURLPOSIXPathStyle, False)
        
        # Open source file
        src_file = ExtAudioFileID()
        if at.ExtAudioFileOpenURL(in_url, ctypes.byref(src_file)) != 0:
            print(f"Failed to open source file: {input_path}")
            return False
        
        # Get source client format info
        # This is complex - we'd need to define CAStreamDescription, etc.
        # Let me try a simpler approach
        
        print("Using raw file manipulation instead...")
        cf.CFRelease(in_url)
        cf.CFRelease(out_url)
        return False
    except Exception as e:
        print(f"Error: {e}")
        return False

# If CoreAudio approach fails, use raw file manipulation
def trim_caf_raw(input_path, output_path, max_seconds):
    """
    CAF format:
    - Header contains chunks and metadata
    - Audio data follows the header
    - Audio size is stored in the header metadata
    
    For our CAF files (created by afconvert):
    - Audio starts at offset 4096
    - Audio size is stored at offset 0xFF8 as 64-bit big-endian
    """
    with open(input_path, 'rb') as f:
        data = f.read()
    
    header_size = 4096
    audio_start = header_size
    
    # Parse desc chunk to get format
    # desc chunk is at offset 8 (right after 'caff' + version)
    # desc size is at offset 12
    # desc data starts at offset 16
    
    # Wait, looking at the hex dump again:
    # 0000: caff 0001 0000 6465 7363 0000 0000 ...
    # This is: magic(4) + version(4) + 'desc'(4) + size(4) + data
    
    # Actually, 'desc' IS a chunk. The CAF format stores chunks right after the magic+version.
    # Each chunk: 4-byte type + 4-byte size + data
    
    # So: offset 8 = 'desc', offset 12 = size = 0 (this is wrong!)
    
    # Wait, that can't be right. Let me look at the actual file differently.
    
    # The CAF format header structure is:
    # bytes 0-3: 'caff'
    # bytes 4-7: version (always 0x00010000)
    # bytes 8+: chunks
    
    # Each chunk: 4-byte type + 4-byte size + size bytes of data
    
    pos = 8
    while pos + 8 <= len(data):
        chunk_type = data[pos:pos+4]
        try:
            type_str = chunk_type.decode('ascii')
        except:
            break
        
        if pos + 8 >= len(data):
            break
            
        chunk_size = int.from_bytes(data[pos+4:pos+8], 'big')
        
        if type_str == 'desc':
            desc_data = data[pos+8:pos+8+chunk_size]
            if len(desc_data) >= 44:
                sample_rate = int.from_bytes(desc_data[36:44], 'big')
                channels = int.from_bytes(desc_data[28:32], 'big')
                bits = int.from_bytes(desc_data[32:36], 'big')
                
                bytes_per_second = sample_rate * channels * (bits // 8)
                max_audio_bytes = int(max_seconds * bytes_per_second)
                
                # Find audio data chunk
                # Search for 'data' in the remaining data
                audio_offset = data.find(b'data', pos)
                if audio_offset > 0:
                    # 'data' is followed by size field
                    size_field = audio_offset + 4
                    old_audio_bytes = int.from_bytes(data[size_field:size_field+8], 'big')
                    old_duration = old_audio_bytes / bytes_per_second
                    
                    if old_audio_bytes <= max_audio_bytes:
                        print(f"Already OK: {old_duration:.1f}s")
                        return True
                    
                    # Create new file: everything up to size field + new size + trimmed audio
                    new_data = data[:size_field] + max_audio_bytes.to_bytes(8, 'big') + \
                               data[audio_offset + 12:audio_offset + 12 + max_audio_bytes]
                    
                    with open(output_path, 'wb') as f:
                        f.write(new_data)
                    
                    print(f"Trimmed: {old_duration:.1f}s -> {max_audio_bytes/bytes_per_second:.1f}s -> {output_path}")
                    return True
                break
        
        pos += 8 + chunk_size
    
    print("Could not find audio data")
    return False

if __name__ == '__main__':
    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else input_path
    max_secs = float(sys.argv[3]) if len(sys.argv) > 3 else 29.0
    
    if not trim_caf_raw(input_path, output_path, max_secs):
        print("Trim failed")
        sys.exit(1)
