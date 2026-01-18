// lib/core/user_fields/hr_field_definition.dart
// Catalogo completo campi HR

import 'hr_field_types.dart';

class HrFieldCatalog {
  static const List<HrField> fields = [

    // =========================
    // 1️⃣ DATI ANAGRAFICI
    // =========================
    HrField(
      key: 'firstName',
      label: 'Nome',
      category: 'Dati anagrafici',
      type: HrFieldType.text,
      target: HrTarget.user,
      required: true,
    ),
    HrField(
      key: 'lastName',
      label: 'Cognome',
      category: 'Dati anagrafici',
      type: HrFieldType.text,
      target: HrTarget.user,
      required: true,
    ),
    HrField(
      key: 'gender',
      label: 'Sesso',
      category: 'Dati anagrafici',
      type: HrFieldType.select,
      target: HrTarget.user,
      options: ['Maschio', 'Femmina', 'Altro'],
    ),
    HrField(
      key: 'birthDate',
      label: 'Data di nascita',
      category: 'Dati anagrafici',
      type: HrFieldType.date,
      target: HrTarget.user,
    ),
    HrField(
      key: 'birthPlace',
      label: 'Luogo di nascita',
      category: 'Dati anagrafici',
      type: HrFieldType.text,
      target: HrTarget.user,
    ),
    HrField(
      key: 'codiceFiscale',
      label: 'Codice fiscale',
      category: 'Dati anagrafici',
      type: HrFieldType.text,
      target: HrTarget.user,
      sensitive: true,
    ),
    HrField(
      key: 'citizenship',
      label: 'Cittadinanza',
      category: 'Dati anagrafici',
      type: HrFieldType.text,
      target: HrTarget.user,
    ),
    HrField(
      key: 'maritalStatus',
      label: 'Stato civile',
      category: 'Dati anagrafici',
      type: HrFieldType.select,
      target: HrTarget.user,
      options: ['Celibe/Nubile', 'Sposato/a', 'Separato/a', 'Divorziato/a'],
    ),

    // =========================
    // 2️⃣ DATI DI CONTATTO
    // =========================
    HrField(
      key: 'addressResidence',
      label: 'Indirizzo di residenza',
      category: 'Dati di contatto',
      type: HrFieldType.address,
      target: HrTarget.user,
    ),
    HrField(
      key: 'addressDomicile',
      label: 'Domicilio',
      category: 'Dati di contatto',
      type: HrFieldType.address,
      target: HrTarget.user,
    ),
    HrField(
      key: 'emailPersonal',
      label: 'Email personale',
      category: 'Dati di contatto',
      type: HrFieldType.text,
      target: HrTarget.user,
    ),
    HrField(
      key: 'emailCompany',
      label: 'Email aziendale',
      category: 'Dati di contatto',
      type: HrFieldType.text,
      target: HrTarget.member,
    ),
    HrField(
      key: 'phone',
      label: 'Telefono',
      category: 'Dati di contatto',
      type: HrFieldType.text,
      target: HrTarget.user,
    ),
    HrField(
      key: 'emergencyContact',
      label: 'Contatto di emergenza',
      category: 'Dati di contatto',
      type: HrFieldType.multiline,
      target: HrTarget.user,
    ),

    // =========================
    // 3️⃣ DATI CONTRATTUALI
    // =========================
    HrField(
      key: 'hireDate',
      label: 'Data di assunzione',
      category: 'Dati contrattuali',
      type: HrFieldType.date,
      target: HrTarget.member,
      required: true,
    ),
    HrField(
      key: 'contractType',
      label: 'Tipo di contratto',
      category: 'Dati contrattuali',
      type: HrFieldType.select,
      target: HrTarget.member,
      options: [
        'Tempo indeterminato',
        'Tempo determinato',
        'Apprendistato',
        'Stage',
      ],
    ),
    HrField(
      key: 'jobRole',
      label: 'Mansione / Ruolo',
      category: 'Dati contrattuali',
      type: HrFieldType.text,
      target: HrTarget.member,
    ),
    HrField(
      key: 'department',
      label: 'Reparto / Gruppo di lavoro',
      category: 'Dati contrattuali',
      type: HrFieldType.text,
      target: HrTarget.member,
    ),
    HrField(
      key: 'employmentStatus',
      label: 'Stato del rapporto',
      category: 'Dati contrattuali',
      type: HrFieldType.select,
      target: HrTarget.member,
      options: ['Attivo', 'Sospeso', 'Cessato'],
    ),
    HrField(
      key: 'terminationDate',
      label: 'Data di cessazione',
      category: 'Dati contrattuali',
      type: HrFieldType.date,
      target: HrTarget.member,
    ),

    // =========================
    // 10️⃣ GDPR / CONSENSI
    // =========================
    HrField(
      key: 'privacyConsent',
      label: 'Consenso privacy',
      category: 'GDPR',
      type: HrFieldType.boolean,
      target: HrTarget.user,
      required: true,
    ),
    HrField(
      key: 'privacyConsentDate',
      label: 'Data consenso',
      category: 'GDPR',
      type: HrFieldType.date,
      target: HrTarget.user,
    ),
    HrField(
      key: 'photoConsent',
      label: 'Consenso uso foto',
      category: 'GDPR',
      type: HrFieldType.boolean,
      target: HrTarget.user,
    ),
  ];
}
