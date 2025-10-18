import ArgumentParser

enum RenderWorkflowError: Error {
    case builder(RunnerBuilder.BuilderError)
    case simulator(SimulatorManager.ManagerError)
    case pipeline(RunnerPipeline.PipelineError)
    case dependencies(DependencyBuilder.BuilderError)
}

enum RenderErrorMapper {
    static func exitCode(for error: RenderWorkflowError) -> ExitCode {
        switch error {
        case .builder:
            return ExitCode(2)
        case .simulator(let managerError):
            return exitCode(for: managerError)
        case .pipeline(let pipelineError):
            return pipelineError.exitCode
        case .dependencies:
            return ExitCode(2)
        }
    }

    private static func exitCode(for error: SimulatorManager.ManagerError) -> ExitCode {
        switch error {
        case .missingDeviceArguments:
            return ExitCode(1)
        default:
            return ExitCode(3)
        }
    }
}
