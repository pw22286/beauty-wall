require 'xcodeproj'

project_path = '/Users/wang/Space/beauty_wall/beauty_wall.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Helper to add files to group and target
def add_file_to_project(project, target, file_path, group_path)
  group = project.main_group.find_subpath(group_path, true)
  group.set_source_tree('<group>')
  file_ref = group.new_reference(file_path)
  target.add_file_references([file_ref])
end

# Define source directory
src_dir = '/Users/wang/Space/beauty_wall/beauty_wall'

# Add files
add_file_to_project(project, target, "#{src_dir}/Core/WallpaperProvider.swift", 'beauty_wall/Core')
add_file_to_project(project, target, "#{src_dir}/Core/WallpaperManager.swift", 'beauty_wall/Core')
add_file_to_project(project, target, "#{src_dir}/Providers/WallhavenProvider.swift", 'beauty_wall/Providers')
add_file_to_project(project, target, "#{src_dir}/Providers/UnsplashProvider.swift", 'beauty_wall/Providers')

project.save
puts "Successfully added new files to Xcode project."
