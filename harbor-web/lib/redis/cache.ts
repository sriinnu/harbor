import { redis } from './client'

export interface CacheOptions {
  ttl?: number // Time to live in seconds
  tags?: string[] // Cache tags for invalidation
}

const DEFAULT_TTL = 3600 // 1 hour

export class RedisCache {
  /**
   * Get a value from cache
   */
  static async get<T>(key: string): Promise<T | null> {
    try {
      const value = await redis.get(key)
      if (!value) return null
      return JSON.parse(value) as T
    } catch (error) {
      console.error('Redis get error:', error)
      return null
    }
  }

  /**
   * Set a value in cache
   */
  static async set(
    key: string,
    value: any,
    options: CacheOptions = {}
  ): Promise<void> {
    try {
      const ttl = options.ttl ?? DEFAULT_TTL
      const serialized = JSON.stringify(value)

      await redis.setex(key, ttl, serialized)

      // Store tags for later invalidation
      if (options.tags) {
        for (const tag of options.tags) {
          await redis.sadd(`tag:${tag}`, key)
          await redis.expire(`tag:${tag}`, ttl)
        }
      }
    } catch (error) {
      console.error('Redis set error:', error)
    }
  }

  /**
   * Delete a value from cache
   */
  static async delete(key: string): Promise<void> {
    try {
      await redis.del(key)
    } catch (error) {
      console.error('Redis delete error:', error)
    }
  }

  /**
   * Invalidate cache by tag
   */
  static async invalidateByTag(tag: string): Promise<void> {
    try {
      const keys = await redis.smembers(`tag:${tag}`)
      if (keys.length > 0) {
        await redis.del(...keys)
      }
      await redis.del(`tag:${tag}`)
    } catch (error) {
      console.error('Redis invalidate by tag error:', error)
    }
  }

  /**
   * Check if a key exists
   */
  static async exists(key: string): Promise<boolean> {
    try {
      const result = await redis.exists(key)
      return result === 1
    } catch (error) {
      console.error('Redis exists error:', error)
      return false
    }
  }

  /**
   * Get or set pattern - execute a function and cache the result
   */
  static async getOrSet<T>(
    key: string,
    fn: () => Promise<T>,
    options: CacheOptions = {}
  ): Promise<T> {
    const cached = await this.get<T>(key)
    if (cached !== null) {
      return cached
    }

    const value = await fn()
    await this.set(key, value, options)
    return value
  }
}

export default RedisCache
