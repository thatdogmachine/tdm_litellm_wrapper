#!/usr/bin/env python3
"""
Direct Redis TTL investigation to understandLiteLLM cache behavior.
This will check actual Redis settings and LiteLLm cache configuration.
"""

import subprocess
import json

def get_redis_config():
    """Get Redis server configuration"""
    print("=== Redis Server Configuration ===")
    
    try:
        # Get all config values
        result = subprocess.run(['redis-cli', 'config', 'get', '*'], capture_output=True, text=True)
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            
            # Look for cache-related settings
            ttl_settings = []
            maxmemory = None
            
            for i in range(0, len(lines), 2):
                if i + 1 < len(lines):
                    key = lines[i].strip()
                    value = lines[i + 1].strip()
                    
                    if 'maxmemory' in key.lower():
                        maxmemory = value
                    elif 'ttl' in key.lower() or 'expire' in key.lower():
                        ttl_settings.append(f"{key}: {value}")
            
            print(f"Max Memory: {maxmemory or 'unlimited'}")
            print("\nTTL/Expiry Settings:")
            for setting in ttl_settings:
                print(f"  {setting}")
                
    except Exception as e:
        print(f"Error getting Redis config: {e}")

def get_current_cache_stats():
    """Get current cache statistics"""
    print("\n=== Current Cache Statistics ===")
    
    try:
        result = subprocess.run(['redis-cli', 'info', 'stats'], capture_output=True, text=True)
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            
            stats = {}
            for line in lines:
                if ':' in line and not line.startswith('#'):
                    key, value = line.split(':', 1)
                    stats[key] = int(value) if value.isdigit() else value
            
            print(f"Keyspace hits: {stats.get('keyspace_hits', 0)}")
            print(f"Keyspace misses: {stats.get('keyspace_misses', 0)}")
            print(f"Total commands processed: {stats.get('total_commands_processed', 0)}")
            
            if stats.get('keyspace_hits', 0) > 0:
                hit_rate = (stats['keyspace_hits'] / (stats.get('keyspace_hits', 0) + stats.get('keyspace_misses', 1))) * 100
                print(f"Cache hit rate: {hit_rate:.2f}%")
            
    except Exception as e:
        print(f"Error getting cache stats: {e}")

def check_cache_entries():
    """Check existing cache entries and their TTLs"""
    print("\n=== Cache Entries Analysis ===")
    
    try:
        # Get all keys
        result = subprocess.run(['redis-cli', 'keys', '*'], capture_output=True, text=True)
        if result.returncode == 0:
            keys = result.stdout.strip().split('\n') if result.stdout.strip() else []
            
            print(f"Total Redis keys: {len(keys)}")
            
            # Check TTLs for all keys
            ttl_values = []
            cache_keys = []
            
            for key in keys:
                try:
                    # Get TTL
                    ttl_result = subprocess.run(['redis-cli', 'ttl', key], capture_output=True, text=True)
                    if ttl_result.returncode == 0:
                        ttl = int(ttl_result.stdout.strip())
                        
                        # Only consider positive TTLs (not -1 permanent or -2 expired)
                        if ttl > 0:
                            ttl_values.append(ttl)
                            
                            # Check if key might be a cache entry
                            try:
                                type_result = subprocess.run(['redis-cli', 'type', key], capture_output=True, text=True)
                                if type_result.returncode == 0 and 'string' in type_result.stdout.strip():
                                    cache_keys.append(key)
                            except:
                                pass
                                
                except Exception as e:
                    continue
            
            print(f"Cache-related keys (with TTL > 0): {len(cache_keys)}")
            
            if ttl_values:
                print(f"TTL range: {min(ttl_values)}s to {max(ttl_values)}s")
                print(f"Average TTL: {sum(ttl_values) / len(ttl_values):.1f}s")
                print(f"Most common TTL: {max(set(ttl_values), key=ttl_values.count)}s")
            
            # Show a sample of cache keys with their TTLs
            if cache_keys and len(cache_keys) <= 10:
                print("\nSample cache keys:")
                for key in cache_keys[:5]:
                    try:
                        ttl_result = subprocess.run(['redis-cli', 'ttl', key], capture_output=True, text=True)
                        if ttl_result.returncode == 0:
                            print(f"  {key[:50]}... -> TTL: {ttl_result.stdout.strip()}s")
                    except:
                        pass
                        
    except Exception as e:
        print(f"Error checking cache entries: {e}")

def analyze_ttl_behavior():
    """Analyze what TTL might be causing the issue"""
    print("\n=== TTL Behavior Analysis ===")
    
    # Check default Redis expiry behavior
    try:
        result = subprocess.run(['redis-cli', 'config', 'get', 'default-ttl'], capture_output=True, text=True)
        if result.result == 0:
            print(f"Default TTL: {result.stdout.strip().split()[1] or 'unlimited'}")
    except:
        pass
    
    try:
        result = subprocess.run(['redis-cli', 'config', 'get', 'maxmemory-policy'], capture_output=True, text=True)
        if result.returncode == 0:
            print(f"Maxmemory policy: {result.stdout.strip().split()[1] or 'none'}")
    except:
        pass
    
    print("\nPossible causes of short TTLs:")
    print("1. LiteLLM cache configuration sets low TTL (default might be very short)")
    print("2. Redis server has global expiry settings")
    print("3. Cache entries are being explicitly short-lived for data freshness")
    print("4. Semantic cache with similarity threshold might expire quickly")

def check_litellm_cache_settings():
    """Check LiteLLM-specific cache configuration"""
    print("\n=== LiteLLM Cache Settings ===")
    
    # Read the current config file
    try:
        with open('/Users/ewannisbet/repos/tdm_litellm_wrapper/proxy_server_config-local-example.yaml', 'r') as f:
            config = f.read()
        
        # Look for cache-related settings
        if 'cache:' in config:
            print("Cache configuration found in proxy_server_config.yaml:")
            
            # Extract cache section
            lines = config.split('\n')
            in_cache_section = False
            
            for line in lines:
                if 'cache:' in line and not line.startswith('#'):
                    in_cache_section = True
                    print(f"  {line.strip()}")
                elif in_cache_section and line.startswith(' '):
                    print(f"  {line.strip()}")
                elif in_cache_section and not line.startswith(' '):
                    break
                    
    except Exception as e:
        print(f"Error reading LiteLLM config: {e}")
    
    print("\nRecommendation:")
    print("To extend cache TTL, modify the proxy_server_config.yaml file and add:")
    print("  cache_params:")
    print("    type: 'redis-semantic'")
    print("    similarity_threshold: 0.8")
    print("    redis_semantic_cache_embedding_model: bedrock/amazon.titan-embed-text-v1")
    print("    ttl: 3600  # Add this line to extend TTL to 1 hour")

if __name__ == "__main__":
    print("LiteLLM Redis Cache TTL Investigation")
    print("=" * 50)
    
    get_redis_config()
    get_current_cache_stats() 
    check_cache_entries()
    analyze_ttl_behavior()
    check_litellm_cache_settings()
    
    print("\n" + "=" * 50)
    print("Investigation complete")