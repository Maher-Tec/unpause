enum ProjectStatus {
  activeHealthy,
  paused,
  goingDown,
  restoring,
  unknown,
}

ProjectStatus projectStatusFromString(String? value) {
  switch (value?.toUpperCase()) {
    case 'ACTIVE_HEALTHY':
      return ProjectStatus.activeHealthy;
    case 'PAUSED':
    case 'INACTIVE':
      return ProjectStatus.paused;
    case 'GOING_DOWN':
      return ProjectStatus.goingDown;
    case 'RESTORING':
      return ProjectStatus.restoring;
    default:
      return ProjectStatus.unknown;
  }
}
