import { describe, expect, it } from 'vitest';
import {
  inviteSchema,
  loginSchema,
  recoverySchema,
  resetPasswordSchema,
} from './validation';

describe('schemas de autenticação', () => {
  it('aceita login válido e rejeita credencial incompleta', () => {
    expect(
      loginSchema.safeParse({ email: 'owner@example.test', password: 'senha' })
        .success
    ).toBe(true);
    expect(
      loginSchema.safeParse({ email: 'não-é-email', password: '' }).success
    ).toBe(false);
  });

  it('aceita recovery com e-mail válido', () => {
    expect(
      recoverySchema.safeParse({ email: 'operator@example.test' }).success
    ).toBe(true);
    expect(recoverySchema.safeParse({ email: 'invalido' }).success).toBe(false);
  });

  it('exige senha mínima e confirmação igual', () => {
    expect(
      resetPasswordSchema.safeParse({
        password: '1234567890',
        confirmation: '1234567890',
      }).success
    ).toBe(true);
    expect(
      resetPasswordSchema.safeParse({ password: '123', confirmation: '123' })
        .success
    ).toBe(false);
    expect(
      resetPasswordSchema.safeParse({
        password: '1234567890',
        confirmation: '1234567891',
      }).success
    ).toBe(false);
  });

  it('aceita somente roles funcionais de convite e nunca office_id', () => {
    expect(
      inviteSchema.safeParse({
        name: 'Operador Teste',
        email: 'operator@example.test',
        role: 'operator',
      }).success
    ).toBe(true);
    expect(
      inviteSchema.safeParse({
        name: 'Operador Teste',
        email: 'operator@example.test',
        role: 'owner',
      }).success
    ).toBe(false);
    expect(
      inviteSchema.safeParse({
        name: 'Operador Teste',
        email: 'operator@example.test',
        role: 'operator',
        office_id: 'arbitrario',
      }).success
    ).toBe(true);
    expect(
      inviteSchema.parse({
        name: 'Operador Teste',
        email: 'operator@example.test',
        role: 'operator',
      })
    ).not.toHaveProperty('office_id');
  });
});
