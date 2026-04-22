// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;

public class MyProject4 : ModuleRules
{
	public MyProject4(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[] {
			"Core",
			"CoreUObject",
			"Engine",
			"InputCore",
			"EnhancedInput",
			"AIModule",
			"StateTreeModule",
			"GameplayStateTreeModule",
			"UMG",
			"Slate"
		});

		PrivateDependencyModuleNames.AddRange(new string[] { });

		PublicIncludePaths.AddRange(new string[] {
			"MyProject4",
			"MyProject4/Variant_Platforming",
			"MyProject4/Variant_Platforming/Animation",
			"MyProject4/Variant_Combat",
			"MyProject4/Variant_Combat/AI",
			"MyProject4/Variant_Combat/Animation",
			"MyProject4/Variant_Combat/Gameplay",
			"MyProject4/Variant_Combat/Interfaces",
			"MyProject4/Variant_Combat/UI",
			"MyProject4/Variant_SideScrolling",
			"MyProject4/Variant_SideScrolling/AI",
			"MyProject4/Variant_SideScrolling/Gameplay",
			"MyProject4/Variant_SideScrolling/Interfaces",
			"MyProject4/Variant_SideScrolling/UI"
		});

		// Uncomment if you are using Slate UI
		// PrivateDependencyModuleNames.AddRange(new string[] { "Slate", "SlateCore" });

		// Uncomment if you are using online features
		// PrivateDependencyModuleNames.Add("OnlineSubsystem");

		// To include OnlineSubsystemSteam, add it to the plugins section in your uproject file with the Enabled attribute set to true
	}
}
