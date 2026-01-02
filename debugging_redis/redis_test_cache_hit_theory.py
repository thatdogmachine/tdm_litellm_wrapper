#!/usr/bin/env python3
"""
Test the cache hit theory: identical requests with minimal delay.
This will prove whether caching works when TTL doesn't expire between requests.
"""

import time
import json
import subprocess
import sys

def test_immediate_cache_hit():
    """Test identical requests with minimal delay"""
    
    # Test prompt
    test_prompt = "What is the capital of France? Please respond with just 'Paris'."
    
    print(f"Testing cache hit theory with prompt: '{test_prompt}'")
    print("=" * 70)
    
    # Get initial cache stats
    cache_stats_before = get_redis_cache_stats()
    print(f"Initial cache hits: {cache_stats_before.get('keyspace_hits', 0)}")
    print(f"Initial cache misses: {cache_stats_before.get('keyspace_misses', 0)}")
    
    # Request 1: Should hit LLM (cache miss)
    print("\n--- Request 1: First request (should hit LLM) ---")
    response1 = make_request(test_prompt)
    
    # Request 2: Should hit cache (immediately after, before TTL expires)
    print("\n--- Request 2: Identical request (should hit cache) ---")
    
    # Minimal delay - just enough for network roundtrip
    time.sleep(0.1)  # 100ms delay
    
    response2 = make_request(test_prompt)
    
    # Request 3: Should also hit cache
    print("\n--- Request 3: Identical request (should also hit cache) ---")
    time.sleep(0.1)
    response3 = make_request(test_prompt)
    
    # Final cache stats
    cache_stats_after = get_redis_cache_stats()
    print("\n" + "=" * 70)
    print("CACHE ANALYSIS")
    print("=" * 70)
    
    cache_hits = cache_stats_after.get('keyspace_hits', 0) - cache_stats_before.get('keyspace_hits', 0)
    cache_misses = cache_stats_after.get('keyspace_misses', 0) - cache_stats_before.get('keyspace_misses', 0)
    
    print(f"Cache hits: {cache_hits}")
    print(f"Cache misses: {cache_misses}")
    
    # Analyze results
    analyze_cache_results(response1, response2, response3, cache_hits, cache_misses)

def make_request(prompt):
    """Make a single request and return response info"""
    cmd = [
        'curl', '-s', '-X', 'POST',
        'http://localhost:4000/v1/chat/completions',
        '-H', 'Content-Type: application/json',
        '-H', 'Authorization: Bearer sk-vyNAFniOpGjMaWdoMcGQQg',
        '-d', json.dumps({
            "model": "local-glm-4-5-air-mlx",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.1,
            "max_tokens": 10
        })
    ]
    
    try:
        start_time = time.time()
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        end_time = time.time()
        
        if result.returncode == 0:
            response = json.loads(result.stdout)
            
            # Extract key info
            tokens_used = response.get('usage', {}).get('total_tokens', 0)
            model = response.get('model', 'unknown')
            elapsed_time = end_time - start_time
            content = response.get('choices', [{}])[0].get('message', {}).get('content')
            
            print(f"[OK] Success")
            print(f"  Model: {model}")
            print(f"  Content: '{content}'")
            print(f"  Tokens used: {tokens_used}")
            print(f"  Response time: {elapsed_time:.3f}s")
            
            return {
                'response': response,
                'model': model,
                'content': content,
                'tokens_used': tokens_used,
                'response_time': elapsed_time
            }
        else:
            print(f" Failed: {result.stderr}")
            return None
            
    except Exception as e:
        print(f" Error: {e}")
        return None

def analyze_cache_results(response1, response2, response3, cache_hits, cache_misses):
    """Analyze the results for cache hit behavior"""
    
    print(f"\n=== CACHE HIT ANALYSIS ===")
    
    # Check if responses are identical
    contents = []
    for i, resp in enumerate([response1, response2, response3], 1):
        if resp:
            contents.append(resp['content'])
    
    print(f"Response content check:")
    for i, content in enumerate(contents, 1):
        print(f"  Request {i}: '{content}'")
    
    # Check if all responses are identical
    all_identical = len(set(contents)) == 1 and None not in contents
    
    print(f"\nAll responses identical: {all_identical}")
    
    # Check response times (cache hits should be faster)
    print(f"\nResponse time analysis:")
    for i, resp in enumerate([response1, response2, response3], 1):
        if resp:
            print(f"  Request {i}: {resp['response_time']:.3f}s")
    
    # Interpret cache behavior
    print(f"\n=== INTERPRETATION ===")
    
    if cache_hits > 0:
        print("[OK] Cache hits detected! Caching is working correctly.")
        print(f"   - Found {cache_hits} cache hits out of total requests")
        
    elif all_identical:
        print("WARNING:  All responses are identical but no cache hits detected.")
        print("   This could indicate:")
        print("   1. Cache entries expire before requests (TTL too short)")
        print("   2. Cache keys are generated differently than expected")
        print("   3. LiteLLM is consistently returning same response for identical prompts")
        
    else:
        print("[ERROR] Responses differ and no cache hits detected.")
        print("   - Cache is either not working or TTL expired")
    
    # Check Redis current state
    check_redis_state()

def get_redis_cache_stats():
    """Get Redis cache statistics"""
    try:
        result = subprocess.run(['redis-cli', 'info', 'stats'], capture_output=True, text=True)
        if result.returncode == 0:
            stats = {}
            for line in result.stdout.split('\n'):
                if ':' in line and not line.startswith('#'):
                    key, value = line.split(':', 1)
                    stats[key] = int(value) if value.isdigit() else value
            return stats
    except Exception as e:
        print(f"Error getting Redis stats: {e}")
    
    return {}

def check_redis_state():
    """Check current Redis key and TTL state"""
    print(f"\n=== REDIS STATE ===")
    
    try:
        # Get all keys
        result = subprocess.run(['redis-cli', 'keys', '*'], capture_output=True, text=True)
        if result.returncode == 0:
            keys = result.stdout.strip().split('\n') if result.stdout.strip() else []
            
            print(f"Total Redis keys: {len(keys)}")
            
            # Check TTLs
            ttl_values = []
            for key in keys[:5]:  # Check first 5 keys
                try:
                    ttl_result = subprocess.run(['redis-cli', 'ttl', key], capture_output=True, text=True)
                    if ttl_result.returncode == 0:
                        ttl = int(ttl_result.stdout.strip())
                        if ttl > 0:
                            ttl_values.append(ttl)
                except:
                    pass
            
            if ttl_values:
                print(f"Sample TTLs: {ttl_values} seconds")
                
    except Exception as e:
        print(f"Error checking Redis state: {e}")

if __name__ == "__main__":
    print("LiteLLM Cache Hit Theory Test")
    print("=" * 70)
    print("Theory: First request hits LLM, second identical request should hit cache")
    print("=" * 70)
    
    test_immediate_cache_hit()
    
    print("\n" + "=" * 70)
    print("Test completed")