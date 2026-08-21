import { z } from 'zod';

export const allowedInviteRoles = [
  'lawyer',
  'operator',
  'reviewer',
  'auditor',
] as const;

export const loginSchema = z.object({
  email: z.string().email('Informe um e-mail válido.'),
  password: z.string().min(1, 'Informe sua senha.'),
});

export const recoverySchema = z.object({
  email: z.string().email('Informe um e-mail válido.'),
});

export const resetPasswordSchema = z
  .object({
    password: z
      .string()
      .min(10, 'A nova senha deve ter pelo menos 10 caracteres.'),
    confirmation: z.string().min(10, 'Confirme a nova senha.'),
  })
  .refine((values) => values.password === values.confirmation, {
    message: 'As senhas precisam ser iguais.',
    path: ['confirmation'],
  });

export const inviteSchema = z.object({
  name: z.string().min(2, 'O nome deve ter pelo menos 2 caracteres.'),
  email: z.string().email('E-mail inválido.'),
  role: z.enum(allowedInviteRoles),
});

export type InviteRole = (typeof allowedInviteRoles)[number];
