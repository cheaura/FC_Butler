import 'package:flutter/material.dart';

/// 포지션 매핑 (웹 squad.js ROLE_SPPOS / ROLE_COORD 이식) — 스쿼드 탭·경기 분석 공용

/// spPosition(0~27) → 역할 코드
const Map<int, String> kSpposRole = {
  0: 'gk', 1: 'sw', 2: 'rwb', 3: 'rb', 4: 'rcb', 5: 'cb', 6: 'lcb',
  7: 'lb', 8: 'lwb', 9: 'rdm', 10: 'cdm', 11: 'ldm', 12: 'rm', 13: 'rcm',
  14: 'cm', 15: 'lcm', 16: 'lm', 17: 'ram', 18: 'cam', 19: 'lam',
  20: 'rf', 21: 'cf', 22: 'lf', 23: 'rw', 24: 'rs', 25: 'st', 26: 'ls', 27: 'lw',
};

/// 역할 → 필드 좌표 (x 0~100, y 수비 -15 ~ 공격 85)
const Map<String, List<double>> kRoleCoord = {
  'gk': [50, -15], 'sw': [50, 0],
  'rwb': [90, 22], 'rb': [93, 10], 'rcb': [68, 10], 'cb': [50, 10],
  'lcb': [32, 10], 'lb': [7, 10], 'lwb': [10, 22],
  'rdm': [70, 38], 'cdm': [50, 38], 'ldm': [30, 38],
  'rm': [93, 55], 'rcm': [73, 55], 'cm': [50, 55], 'lcm': [27, 55], 'lm': [7, 55],
  'ram': [80, 72], 'cam': [50, 72], 'lam': [20, 72],
  'rf': [75, 80], 'cf': [50, 82], 'lf': [25, 80],
  'rw': [87, 80], 'rs': [70, 85], 'st': [50, 85], 'ls': [30, 85], 'lw': [13, 80],
};

/// 포지션 계열색 (GK 노랑 / DF 파랑 / MF 초록 / FW 빨강)
Color posColor(int spPos) {
  if (spPos == 0) return Colors.amber.shade700;
  if (spPos <= 8) return Colors.blue.shade600;
  if (spPos <= 19) return Colors.green.shade600;
  return Colors.red.shade600;
}

/// 강화 단계색 (1 회백 / 2~4 브론즈 / 5~7 실버 / 8~10 골드).
/// 11~13은 색 근사가 아니라 넥슨 플래티넘 판 이미지 사용 — GradeBadge 위젯을 쓸 것.
Color gradeColor(int grade) {
  if (grade >= 11) return const Color(0xFFD8E4E8); // 폴백 근사색 (배지는 이미지)
  if (grade >= 8) return const Color(0xFFF5C842);
  if (grade >= 5) return const Color(0xFFC0C0C0);
  if (grade >= 2) return const Color(0xFFCD8B57);
  return const Color(0xFF9E9E9E);
}

/// 강화 단계별 OVR 보너스 (utils/squad_maker.py GRADE_BONUS와 동일 — 대조 유지)
const Map<int, int> kGradeBonus = {
  0: 0, 1: 3, 2: 4, 3: 5, 4: 7, 5: 9,
  6: 11, 7: 14, 8: 18, 9: 20, 10: 22, 11: 24, 12: 27, 13: 30,
};

/// 적응도별 OVR 보너스 (웹 squad.js ADAP_BONUS와 동일)
const Map<int, int> kAdapBonus = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4};

/// 역할 코드 → spPosition 역매핑 (웹 ROLE_SPPOS와 동일)
const Map<String, int> kRoleSppos = {
  'gk': 0, 'sw': 1, 'rwb': 2, 'rb': 3, 'rcb': 4, 'cb': 5, 'lcb': 6,
  'lb': 7, 'lwb': 8, 'rdm': 9, 'cdm': 10, 'ldm': 11, 'rm': 12, 'rcm': 13,
  'cm': 14, 'lcm': 15, 'lm': 16, 'ram': 17, 'cam': 18, 'lam': 19,
  'rf': 20, 'cf': 21, 'lf': 22, 'rw': 23, 'rs': 24, 'st': 25, 'ls': 26,
  'lw': 27,
};

/// 포메이션 → 역할 11자리 (웹 squad.js FORMATIONS와 동일)
const Map<String, List<String>> kFormations = {
  '4-3-3': ['gk', 'rb', 'rcb', 'lcb', 'lb', 'rcm', 'cm', 'lcm', 'rw', 'st', 'lw'],
  '4-1-2-3': ['gk', 'rb', 'rcb', 'lcb', 'lb', 'cdm', 'rcm', 'lcm', 'ram', 'cam', 'lam'],
  '4-2-3-1': ['gk', 'rb', 'rcb', 'lcb', 'lb', 'rdm', 'ldm', 'ram', 'cam', 'lam', 'st'],
  '4-4-2': ['gk', 'rb', 'rcb', 'lcb', 'lb', 'rm', 'rcm', 'lcm', 'lm', 'rs', 'ls'],
  '4-1-4-1': ['gk', 'rb', 'rcb', 'lcb', 'lb', 'cdm', 'rm', 'rcm', 'lcm', 'lm', 'st'],
  '4-2-4': ['gk', 'rb', 'rcb', 'lcb', 'lb', 'rcm', 'lcm', 'rw', 'rs', 'ls', 'lw'],
  '3-5-2': ['gk', 'rcb', 'cb', 'lcb', 'rm', 'rcm', 'cm', 'lcm', 'lm', 'rs', 'ls'],
  '5-3-2': ['gk', 'rwb', 'rcb', 'cb', 'lcb', 'lwb', 'rcm', 'cm', 'lcm', 'rs', 'ls'],
};

/// 랭커픽 포지션 매칭 우선순위 (정확 일치 → 같은 계열 폴백 — 웹 ROLE_FALLBACK과 동일)
const Map<String, List<String>> kRoleFallback = {
  'gk': ['GK'],
  'st': ['ST', 'RS', 'LS', 'CF', 'RF', 'LF', 'CAM'],
  'rs': ['RS', 'ST', 'LS', 'CF', 'RW', 'RF'],
  'ls': ['LS', 'ST', 'RS', 'CF', 'LW', 'LF'],
  'cf': ['CF', 'ST', 'RS', 'LS', 'CAM', 'RF', 'LF'],
  'rf': ['RF', 'RW', 'CF', 'RS', 'ST'],
  'lf': ['LF', 'LW', 'CF', 'LS', 'ST'],
  'rw': ['RW', 'RF', 'RM', 'RS', 'RAM', 'ST'],
  'lw': ['LW', 'LF', 'LM', 'LS', 'LAM', 'ST'],
  'cam': ['CAM', 'RAM', 'LAM', 'CF', 'CM', 'ST'],
  'ram': ['RAM', 'CAM', 'RM', 'RW', 'RCM'],
  'lam': ['LAM', 'CAM', 'LM', 'LW', 'LCM'],
  'rm': ['RM', 'RW', 'RAM', 'RCM', 'RF'],
  'lm': ['LM', 'LW', 'LAM', 'LCM', 'LF'],
  'cm': ['CM', 'RCM', 'LCM', 'CDM', 'CAM'],
  'rcm': ['RCM', 'CM', 'LCM', 'RDM', 'CDM', 'RAM'],
  'lcm': ['LCM', 'CM', 'RCM', 'LDM', 'CDM', 'LAM'],
  'cdm': ['CDM', 'RDM', 'LDM', 'CM', 'RCM', 'LCM'],
  'rdm': ['RDM', 'CDM', 'LDM', 'RCM', 'CM'],
  'ldm': ['LDM', 'CDM', 'RDM', 'LCM', 'CM'],
  'rb': ['RB', 'RWB', 'RCB', 'RM'],
  'lb': ['LB', 'LWB', 'LCB', 'LM'],
  'rwb': ['RWB', 'RB', 'RM', 'RCB'],
  'lwb': ['LWB', 'LB', 'LM', 'LCB'],
  'rcb': ['RCB', 'CB', 'LCB', 'SW', 'RB'],
  'lcb': ['LCB', 'CB', 'RCB', 'SW', 'LB'],
  'cb': ['CB', 'RCB', 'LCB', 'SW'],
  'sw': ['SW', 'CB', 'RCB', 'LCB'],
};
