import init, { Simulator } from '../../simulator/pkg/xisa_simulator.js';

let simulator: Simulator | null = null;
let initialized = false;

export async function getSimulator(): Promise<Simulator> {
  if (!initialized) {
    await init();
    initialized = true;
  }
  if (!simulator) {
    simulator = new Simulator();
  }
  return simulator;
}

export function resetSimulator(): void {
  if (simulator) {
    simulator.reset();
  }
}
