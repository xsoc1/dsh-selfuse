import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it, vi } from 'vitest'
import { spawnSubprocess } from '../src/spawn.ts'

const { spawnMock } = vi.hoisted(() => ({
  spawnMock: vi.fn(),
}))

vi.mock('node:child_process', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:child_process')>()
  const wrapped = (...args: Parameters<typeof import('node:child_process').spawn>) => actual.spawn(...args)
  spawnMock.mockImplementation(wrapped as any)
  return { ...actual, spawn: spawnMock }
})

const spillDir = mkdtempSync(join(tmpdir(), 'dsh-subprocess-windows-spec-'))

describe('spawnSubprocess windows console behavior', () => {
  it('hides child console windows on Windows hosts', async () => {
    const running = spawnSubprocess({
      argv: [process.execPath, '-e', 'process.exit(0)'],
      cwd: process.cwd(),
      stdio: {
        stdin: 'ignore',
        stdout: { maxBytes: 64_000, spill: { maxBytes: 64 * 1024 * 1024 } },
        stderr: { maxBytes: 64_000, spill: { maxBytes: 64 * 1024 * 1024 } },
      },
      graceMs: 3_000,
    }, { spillDir })

    const outcome = await running.done
    expect(outcome.exitCode).toBe(0)
    const [, , options] = spawnMock.mock.calls[0]!
    expect(options.windowsHide).toBe(true)
  })
})
